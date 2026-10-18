#!/usr/bin/env python3
"""Drives `vocoder bridge-demo` in a pseudo-terminal and checks the UI bridge end to end, plus a
smoke test of the app itself (`vocoder`, `vocoder --demo`).

Not part of `make test` (FTXUI waits ~500 ms for terminal replies at startup in a bare pty).
Run: `make pty-test` or `python3 -I scripts/bridge-pty-test.py [path/to/vocoder]`.

A minimal VT emulator replays the bytes the TUI writes, so the on-screen result can be compared
with the bridge's off-screen render of the same tree (P1-02 acceptance).
"""

import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# MARK: - Minimal VT emulator


class Screen:
    """Just enough of a VT100/xterm to replay FTXUI's output: cursor movement, erase, UTF-8 with
    wide characters, alternate screen. Attributes (SGR) are ignored."""

    def __init__(self, width, height):
        self.width, self.height = width, height
        self.alt = False
        self.entered_alt = self.left_alt = False
        self.cursor_visible = True
        self._pending = b""
        self.clear()

    def clear(self):
        self.cells = [[" "] * self.width for _ in range(self.height)]
        self.x = self.y = 0

    def resize(self, width, height):
        old = self.cells
        self.width, self.height = width, height
        self.cells = [[" "] * width for _ in range(height)]
        for y in range(min(height, len(old))):
            for x in range(min(width, len(old[y]))):
                self.cells[y][x] = old[y][x]
        self.x, self.y = min(self.x, width - 1), min(self.y, height - 1)

    def text(self):
        rows = []
        for row in self.cells:
            rows.append("".join(c for c in row if c is not None).rstrip(" "))
        return "\n".join(rows) + "\n"

    def feed(self, data):
        data = self._pending + data
        self._pending = b""
        i = 0
        n = len(data)
        while i < n:
            b = data[i]
            if b == 0x1B:
                end = self._escape(data, i)
                if end is None:
                    self._pending = data[i:]
                    return
                i = end
            elif b == 0x0D:
                self.x = 0
                i += 1
            elif b == 0x0A:
                self._linefeed()
                i += 1
            elif b == 0x08:
                self.x = max(0, self.x - 1)
                i += 1
            elif b < 0x20 or b == 0x7F:
                i += 1  # NUL (FTXUI flush marker), BEL, …
            else:
                length = 1 if b < 0x80 else 2 if b < 0xE0 else 3 if b < 0xF0 else 4
                if i + length > n:
                    self._pending = data[i:]
                    return
                self._put(data[i : i + length].decode("utf-8", "replace"))
                i += length

    def _linefeed(self):
        if self.y == self.height - 1:
            self.cells.pop(0)
            self.cells.append([" "] * self.width)
        else:
            self.y += 1

    def _put(self, ch):
        wide = unicodedata.east_asian_width(ch) in ("W", "F")
        if unicodedata.combining(ch) or ch == "️":
            return
        if self.x >= self.width:
            return
        self.cells[self.y][self.x] = ch
        if wide and self.x + 1 < self.width:
            self.cells[self.y][self.x + 1] = None  # covered by the wide glyph
        self.x += 2 if wide else 1

    def _escape(self, data, i):
        """Handles the sequence at data[i] (ESC). Returns the index after it, or None if
        incomplete."""
        if i + 1 >= len(data):
            return None
        kind = data[i + 1]
        if kind == ord("["):
            j = i + 2
            while j < len(data) and not (0x40 <= data[j] <= 0x7E):
                j += 1
            if j >= len(data):
                return None
            self._csi(data[i + 2 : j].decode("latin-1"), chr(data[j]))
            return j + 1
        if kind in (ord("]"), ord("P")):  # OSC / DCS: until BEL or ST
            j = i + 2
            while j < len(data):
                if data[j] == 0x07:
                    return j + 1
                if data[j] == 0x1B and j + 1 < len(data) and data[j + 1] == ord("\\"):
                    return j + 2
                j += 1
            return None
        if kind in (ord("("), ord(")")):
            return i + 3 if i + 2 < len(data) else None
        return i + 2  # ESC 7, ESC 8, ESC =, …

    def _csi(self, params, final):
        private = params.startswith("?")
        nums = [int(p) if p.isdigit() else 0 for p in params.lstrip("?>").split(";")] if params else []
        first = nums[0] if nums else 0
        count = max(1, first)
        if private and final in "hl":
            on = final == "h"
            if 1049 in nums:
                self.alt = on
                if on:
                    self.entered_alt = True
                    self.clear()
                else:
                    self.left_alt = True
            if 25 in nums:
                self.cursor_visible = on
        elif final in "Hf":
            row = (nums[0] if len(nums) > 0 and nums[0] else 1) - 1
            col = (nums[1] if len(nums) > 1 and nums[1] else 1) - 1
            self.y, self.x = min(row, self.height - 1), min(col, self.width - 1)
        elif final == "A":
            self.y = max(0, self.y - count)
        elif final == "B":
            self.y = min(self.height - 1, self.y + count)
        elif final == "C":
            self.x = min(self.width - 1, self.x + count)
        elif final == "D":
            self.x = max(0, self.x - count)
        elif final == "G":
            self.x = min(self.width - 1, count - 1)
        elif final == "K":
            row = self.cells[self.y]
            span = range(self.x, self.width) if first == 0 else range(0, self.x + 1) if first == 1 else range(self.width)
            for x in span:
                row[x] = " "
        elif final == "J":
            if first == 2 or first == 3:
                self.cells = [[" "] * self.width for _ in range(self.height)]
            elif first == 0:
                for x in range(self.x, self.width):
                    self.cells[self.y][x] = " "
                for y in range(self.y + 1, self.height):
                    self.cells[y] = [" "] * self.width


# MARK: - Driving the demo


class Demo:
    """Runs the demo under a tiny `sh` wrapper that records the tty modes (`stty -g`) before and
    after: when the session leader exits, macOS revokes the pty, so the parent can't check."""

    def __init__(self, binary, args=(), width=80, height=24, env=None, command=("bridge-demo",)):
        self.screen = Screen(width, height)
        self.raw = b""
        self.tmp = tempfile.TemporaryDirectory()
        self.before = os.path.join(self.tmp.name, "before")
        self.after = os.path.join(self.tmp.name, "after")
        self.master, self.slave = pty.openpty()
        self._winsize(width, height)
        # Hermetic: never the user's config (a missing file means defaults).
        child_env = dict(
            os.environ, TERM="xterm-256color", VOCODER_CONFIG=os.path.join(self.tmp.name, "config.toml")
        )
        child_env.update(env or {})
        for key in list(child_env):
            if key.startswith("CLAUDE") or key == "TERM_PROGRAM":
                child_env.pop(key)
        script = 'stty -g > "$0.before"; "$@"; code=$?; stty -g > "$0.after"; exit $code'
        self.proc = subprocess.Popen(
            ["/bin/sh", "-c", script, os.path.join(self.tmp.name, "modes"), binary, *command, *args],
            stdin=self.slave,
            stdout=self.slave,
            stderr=self.slave,
            env=child_env,
            start_new_session=True,
            preexec_fn=self._controlling_tty,
        )
        self.before = os.path.join(self.tmp.name, "modes.before")
        self.after = os.path.join(self.tmp.name, "modes.after")

    def demo_pid(self):
        """The vocoder process (child of the wrapper)."""
        deadline = time.time() + 5
        while time.time() < deadline:
            out = subprocess.run(["pgrep", "-P", str(self.proc.pid)], capture_output=True, text=True)
            if out.stdout.strip():
                return int(out.stdout.split()[0])
            time.sleep(0.05)
        raise AssertionError("demo process not found")

    def signal(self, sig):
        os.kill(self.demo_pid(), sig)

    def _controlling_tty(self):
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    def _winsize(self, width, height):
        fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, 0, 0))

    def resize(self, width, height):
        self._winsize(width, height)  # the kernel sends SIGWINCH to the foreground group
        self.screen.resize(width, height)

    def pump(self, seconds=0.05):
        deadline = time.time() + seconds
        while True:
            left = deadline - time.time()
            if left <= 0:
                return
            ready, _, _ = select.select([self.master], [], [], left)
            if ready:
                try:
                    chunk = os.read(self.master, 65536)
                except OSError:
                    return
                if not chunk:
                    return
                self.raw += chunk
                self.screen.feed(chunk)

    def wait_for(self, predicate, timeout=5.0, what="condition"):
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.pump(0.05)
            if predicate(self.screen.text()):
                return
        raise AssertionError(f"timed out waiting for {what}; screen:\n{self.screen.text()}")

    def send(self, data, settle=0.15):
        os.write(self.master, data.encode() if isinstance(data, str) else data)
        self.pump(settle)

    def wait_exit(self, timeout=5.0):
        """The demo's exit status as the shell reports it (128 + signal when killed)."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.pump(0.05)
            code = self.proc.poll()
            if code is not None:
                self.pump(0.1)
                return code
        self.kill()
        raise AssertionError("demo did not exit")

    def modes_restored(self):
        def modes(path):
            with open(path) as f:
                fields = dict(p.split("=", 1) for p in f.read().strip().split(":")[1:])
            # PENDIN is a transient kernel bit (P0-01 finding); ignore it.
            fields["lflag"] = int(fields["lflag"], 16) & ~termios.PENDIN
            return fields

        return modes(self.before) == modes(self.after)

    def kill(self):
        """Kill the wrapper's whole group: killing only the wrapper orphans the demo (and any
        popped-out shell), which then never sees a hangup because we still hold the pty."""
        try:
            os.killpg(self.proc.pid, signal.SIGKILL)  # start_new_session: pgid == wrapper pid
        except ProcessLookupError:
            pass
        self.proc.wait()

    def close(self):
        self.kill()
        os.close(self.master)
        os.close(self.slave)
        self.tmp.cleanup()


# MARK: - Checks

RESULTS = []


def check(name):
    def wrap(fn):
        RESULTS.append((name, fn))
        return fn

    return wrap


def started(demo):
    demo.wait_for(lambda s: "1:Home" in s and "q/Ctrl-C quit" in s, what="first frame")


def assert_clean_exit(demo, code):
    assert code == 0, f"exit code {code}"
    assert demo.screen.entered_alt and demo.screen.left_alt, "alternate screen not left"
    assert demo.screen.cursor_visible, "cursor left hidden"
    assert demo.modes_restored(), "tty modes not restored"


@check("quit with q restores the terminal")
def _(binary):
    demo = Demo(binary)
    try:
        started(demo)
        demo.send("q")
        assert_clean_exit(demo, demo.wait_exit())
    finally:
        demo.close()


@check("Ctrl-C is a key that quits gracefully")
def _(binary):
    demo = Demo(binary)
    try:
        started(demo)
        demo.send("\x03")
        assert_clean_exit(demo, demo.wait_exit())
    finally:
        demo.close()


for _sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):

    @check(f"{_sig.name} shuts down gracefully")
    def _(binary, sig=_sig):
        demo = Demo(binary)
        try:
            started(demo)
            demo.signal(sig)
            assert_clean_exit(demo, demo.wait_exit())
        finally:
            demo.close()


@check("on-screen matches off-screen render, before and after resize")
def _(binary):
    with tempfile.TemporaryDirectory() as tmp:
        dump = os.path.join(tmp, "offscreen.txt")
        demo = Demo(binary, ["--still", "--dump-offscreen", dump])
        try:
            started(demo)
            for size in [(80, 24), (100, 30), (60, 20)]:
                if size != (80, 24):
                    if os.path.exists(dump):
                        os.remove(dump)
                    demo.resize(*size)
                demo.wait_for(lambda s: os.path.exists(dump), what=f"off-screen dump at {size}")
                demo.pump(0.3)
                with open(dump, encoding="utf-8") as f:
                    offscreen = f.read()
                onscreen = demo.screen.text()
                assert onscreen == offscreen, (
                    f"mismatch at {size}:\n--- on-screen\n{onscreen}--- off-screen\n{offscreen}"
                )
                assert f"Size: {size[0]}×{size[1]}" in onscreen, "resize not reported"
            demo.send("q")
            assert_clean_exit(demo, demo.wait_exit())
        finally:
            demo.close()


@check("each DECRQSS query (Terminal.app prints it as text) is followed by a cursor home")
def _(binary):
    # Terminal.app shows the payload ("$q q"), moving the cursor; FTXUI draws the next frame
    # from the cursor, diff-based, so it would stay shifted. In a bare pty FTXUI redraws
    # everything right after, hiding the shift on screen, so check the byte stream: between
    # each query and the frame after it (FTXUI's Draw starts by hiding the cursor) the bridge
    # sends ESC[H. Covers startup and the return from a pop-out.
    query, frame, home = b"\x1bP$q q\x1b\\", b"\x1b[?25l", b"\x1b[H"
    demo = Demo(binary, ["--still"], env={"SHELL": "/bin/sh"})
    try:
        started(demo)
        demo.send("p", settle=0.5)
        demo.send("exit\r")
        demo.wait_for(lambda s: "q/Ctrl-C quit" in s, what="TUI after pop-out")
        demo.pump(0.3)
        demo.send("q")
        assert_clean_exit(demo, demo.wait_exit())
        queries = 0
        position = demo.raw.find(query)
        while position >= 0:
            queries += 1
            after = position + len(query)
            frame_start = demo.raw.find(frame, after)
            assert frame_start >= 0, f"no frame after query {queries}"
            assert home in demo.raw[after:frame_start], f"no cursor home after query {queries}"
            position = demo.raw.find(query, after)
        assert queries == 2, f"expected 2 queries (startup, pop-out), saw {queries}"
    finally:
        demo.close()


@check("keys: leader, Ctrl-Space, CSI-u, Alt, function keys, UTF-8")
def _(binary):
    demo = Demo(binary, ["--still"])
    try:
        started(demo)
        demo.send("\x005")  # Ctrl-Space 5 → Keys tab
        demo.wait_for(lambda s: "Last keys" in s, what="Keys tab")
        for keys in ["a", "\x00x", "\x1b[105;5u", "\x1bx", "\x1b[15~", "\x1b[A", "é"]:
            demo.send(keys, settle=0.1)
        demo.wait_for(lambda s: "é  [c3 a9]" in s, what="key log")
        screen = demo.screen.text()
        for expected in [
            "a  [61]",
            "Ctrl-Space  [00]",
            "Ctrl-i  [1b 5b 31 30 35 3b 35 75]",
            "Alt-x  [1b 78]",
            "F5  [1b 5b 31 35 7e]",
            "ArrowUp  [1b 5b 41]",
        ]:
            assert expected in screen, f"missing {expected!r} in:\n{screen}"
        demo.send("q")
        assert_clean_exit(demo, demo.wait_exit())
    finally:
        demo.close()


@check("mouse: off by default, reported with --mouse")
def _(binary):
    for args, expect in [(["--still"], False), (["--still", "--mouse"], True)]:
        demo = Demo(binary, args)
        try:
            started(demo)
            assert (b"\x1b[?1000h" in demo.raw) == expect, "mouse reporting mode"
            demo.send("\x005")
            demo.wait_for(lambda s: "Last keys" in s, what="Keys tab")
            demo.send("\x1b[<0;5;3M\x1b[<0;5;3m", settle=0.3)  # left press + release
            screen = demo.screen.text()
            assert ("mouse 1/0 at 4,2" in screen) == expect, f"mouse log ({args}):\n{screen}"
            demo.send("q")
            assert_clean_exit(demo, demo.wait_exit())
        finally:
            demo.close()


@check("input widget: typing, Unicode, submit; widget state survives tab switches")
def _(binary):
    demo = Demo(binary, ["--still"])
    try:
        started(demo)
        demo.send("\x002")
        demo.wait_for(lambda s: "i edits the name" in s, what="Input tab")
        demo.send("i")
        demo.send("héllo 日本")
        demo.wait_for(lambda s: 'Swift sees name: "héllo 日本"' in s, what="typed text")
        demo.send("\r")
        demo.wait_for(lambda s: "Last submitted: name: héllo 日本" in s, what="submit")
        demo.send("\x001")
        demo.send("\x002")
        demo.wait_for(lambda s: "│héllo 日本" in s, what="value after tab switch")
        demo.send("q")
        assert_clean_exit(demo, demo.wait_exit())
    finally:
        demo.close()


@check("pop-out: shell runs with the terminal restored, Ctrl-C there doesn't quit, TUI resumes")
def _(binary):
    demo = Demo(binary, ["--still"], env={"SHELL": "/bin/sh"})
    try:
        started(demo)
        demo.send("p", settle=0.5)
        assert not demo.screen.alt, "still on the alternate screen during pop-out"
        # Ctrl-C must interrupt a program in the shell (signals reset to default in the child)
        # and must not stop the demo, which shares the process group.
        demo.send("sleep 10\r", settle=0.5)
        demo.send("\x03", settle=0.2)
        demo.send("echo POP$((40+2))\r")
        deadline = time.time() + 3
        while b"POP42" not in demo.raw and time.time() < deadline:
            demo.pump(0.05)
        assert b"POP42" in demo.raw, "Ctrl-C did not interrupt sleep in the popped-out shell"
        assert demo.proc.poll() is None, "demo exited during pop-out"
        demo.send("exit\r")
        demo.wait_for(lambda s: "q/Ctrl-C quit" in s, what="TUI after pop-out")
        assert demo.screen.alt, "alternate screen not re-entered"
        demo.send("\x005")
        demo.wait_for(lambda s: "pop-out: /bin/sh exited with 0" in s, what="pop-out log")
        demo.send("q")
        assert_clean_exit(demo, demo.wait_exit())
    finally:
        demo.close()


@check("Swift runtime trap (SIGTRAP) restores the terminal")
def _(binary):
    demo = Demo(binary, ["--still", "--crash-after", "1"])
    try:
        started(demo)
        code = demo.wait_exit(timeout=15)
        assert code == 128 + signal.SIGTRAP, f"expected death by SIGTRAP, got {code}"
        assert demo.screen.left_alt, "alternate screen not left"
        assert demo.screen.cursor_visible, "cursor left hidden"
        assert demo.modes_restored(), "tty modes not restored"
    finally:
        demo.close()


@check("app: vocoder --demo shows the chrome, runs leader keys and a dialog, Ctrl-C quits")
def _(binary):
    app = Demo(binary, command=("--demo",))
    try:
        app.wait_for(lambda s: "1 Home" in s and "voice off" in s and "^P palette" in s, what="chrome")
        app.send("\x00")
        app.wait_for(lambda s: "+Demo" in s, what="which-key popup")
        app.send("3")
        app.wait_for(lambda s: "Demo tasks" in s, what="Tasks tab")
        app.send("\x00du")
        app.wait_for(lambda s: "Publish the demo?" in s, what="confirm dialog")
        app.send("y")
        app.wait_for(lambda s: "Published" in s, what="toast")
        app.send("\x03")
        assert_clean_exit(app, app.wait_exit())
    finally:
        app.close()


@check("app: the demo repo tab streams a turn, asks for approval and answers on 'a'")
def _(binary):
    app = Demo(binary, command=("--demo",), width=100, height=30)
    try:
        app.wait_for(lambda s: "1 Home" in s, what="chrome")
        app.send("\x002")
        app.wait_for(lambda s: "starts with your first prompt" in s or "ready" in s, what="repo tab")
        app.wait_for(lambda s: "Changes (2)" in s, what="git panel")
        app.send("what changed?\r")
        app.wait_for(lambda s: "Allow Bash?" in s and "git status --short" in s, what="approval card")
        app.send("a")
        app.wait_for(lambda s: "Nothing else changed." in s and "── done" in s, what="reply")
        assert "Allow Bash?" not in app.screen.text(), "approval card still shown"
        app.send("\x00q")
        assert_clean_exit(app, app.wait_exit())
    finally:
        app.close()


@check("app: vocoder (no config) shows Home and quits with the leader")
def _(binary):
    app = Demo(binary, command=())
    try:
        app.wait_for(lambda s: "1 Home" in s and "Getting around" in s, what="Home tab")
        app.wait_for(lambda s: "No config file" in s, what="no-config toast")
        app.send("\x00q")
        assert_clean_exit(app, app.wait_exit())
    finally:
        app.close()


@check("app: config reaches the app ([keys] leader replaces Ctrl-Space)")
def _(binary):
    tmp = tempfile.TemporaryDirectory()
    config = os.path.join(tmp.name, "config.toml")
    with open(config, "w") as f:
        f.write('[keys]\nleader = "ctrl+b"\n[ui]\ntheme = "light"\n')
    app = Demo(binary, command=(), env={"VOCODER_CONFIG": config})
    try:
        app.wait_for(lambda s: "1 Home" in s, what="Home tab")
        assert "No config file" not in app.screen.text(), "config not found"
        app.send("\x00")  # Ctrl-Space is no longer the leader: no which-key popup
        assert "1…9" not in app.screen.text(), "Ctrl-Space still opens the leader popup"
        app.send("\x02")
        app.wait_for(lambda s: "1…9" in s, what="which-key popup on Ctrl-B")
        app.send("q")
        assert_clean_exit(app, app.wait_exit())
    finally:
        app.close()
        tmp.cleanup()


@check("app: an invalid config is reported before the TUI starts")
def _(binary):
    tmp = tempfile.TemporaryDirectory()
    config = os.path.join(tmp.name, "bad.toml")
    with open(config, "w") as f:
        f.write('[ui]\ntheme = "solar"\n[keys]\nleader = "hyper"\n')
    app = Demo(binary, command=("--config", config))
    try:
        code = app.wait_exit()
        text = app.raw.decode(errors="replace")  # the screen truncates long lines
        assert code == 1, f"exit code {code}"
        assert not app.screen.entered_alt, "the TUI started"
        assert "2 problems in" in text, text
        assert "bad.toml:2: ui.theme: unknown theme 'solar'" in text, text
        assert "bad.toml:4: keys.leader:" in text, text
        assert app.modes_restored(), "tty modes changed"
    finally:
        app.close()
        tmp.cleanup()


def main():
    binary = sys.argv[1] if len(sys.argv) > 1 else None
    if binary is None:
        bin_dir = subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=ROOT, text=True)
        binary = os.path.join(bin_dir.strip(), "vocoder")
    failures = 0
    for name, fn in RESULTS:
        start = time.time()
        try:
            fn(binary)
            print(f"✔ {name} ({time.time() - start:.1f}s)")
        except AssertionError as error:
            failures += 1
            print(f"✘ {name}: {error}")
    print(f"{len(RESULTS) - failures}/{len(RESULTS)} passed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
