#!/usr/bin/env python3
"""Real-terminal UI checks in Terminal.app (P1-07b): what the pty test can't see.

Opens Terminal.app windows at fixed sizes running `vocoder --demo` and `vocoder ui-gallery`,
sends real keystrokes through System Events (Ctrl-Space, Alt-digits, Ctrl-P, …), compares the
window's text with the app's off-screen render (`$VOCODER_DUMP_SCREEN`), and samples pixel
colours of a window screenshot against the colours the app drew (from the ANSI dump).

Opt-in and slow; never part of `make test`. Takes keyboard focus while it runs: don't type.
Run: `make term-test` or `python3 -I scripts/term-test.py [path/to/vocoder] [-k <filter>]`.

Needs (one-time, for the app running this script, e.g. Terminal or Ghostty): Automation for
Terminal and System Events, Accessibility, Screen Recording. See README.md.

Each scenario runs in a window with its own temporary Terminal profile, imported from a
`.terminal` file and deleted afterwards; the user's profiles and windows are never changed.
Results (screenshots, text dumps) go to `.build/term-test/<timestamp>/`.
"""

import argparse
import json
import os
import re
import shlex
import signal
import struct
import subprocess
import sys
import time
import traceback

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROFILE_PREFIX = "vocoder-term-test-"
SRGB_PROFILE = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"
CALIBRATION = (255, 0, 255)

# Terminal profile colours per theme (the built-in themes use the terminal's default colours).
PROFILE_COLORS = {
    "dark": {"background": (0, 0, 0), "text": (229, 229, 229)},
    "light": {"background": (255, 255, 255), "text": (0, 0, 0)},
}
# Theme roles the checks look for (Sources/VoCoderUI/Style/Theme.swift).
SELECTION = {"dark": (0, 75, 135), "light": (175, 215, 255)}
FOCUS = {"dark": (95, 175, 255), "light": (0, 95, 175)}
CODE_BACKGROUND = {"dark": (38, 38, 38), "light": (238, 238, 238)}

# Per-channel tolerance after converting the screenshot to sRGB.
BG_TOLERANCE = 12
# Cells allowed to differ in a full background check (the cursor, if shown).
BG_SLACK = 2


class CheckFailed(Exception):
    pass


class Warning_(Exception):
    """A check that couldn't run because of the environment, not the app."""


# MARK: - AppleScript


def osascript(script, timeout=20):
    result = subprocess.run(
        ["osascript", "-"], input=script, capture_output=True, text=True, timeout=timeout
    )
    if result.returncode != 0:
        raise RuntimeError(f"osascript failed: {result.stderr.strip()}\n--- script\n{script}")
    return result.stdout.rstrip("\n")


def terminal(expression):
    return osascript(f'tell application "Terminal" to {expression}')


def as_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def color16(rgb):
    return "{" + ", ".join(str(c * 257) for c in rgb) + "}"


# MARK: - Images


def capture(window_id, png_path):
    """Screenshot of the window (no shadow), converted to sRGB; returns an `Image`."""
    subprocess.run(["screencapture", "-x", "-o", f"-l{window_id}", png_path], check=True)
    bmp_path = png_path[:-4] + ".bmp"
    subprocess.run(
        ["sips", "-m", SRGB_PROFILE, "-s", "format", "bmp", png_path, "--out", bmp_path],
        check=True,
        capture_output=True,
    )
    image = Image.read_bmp(bmp_path)
    os.remove(bmp_path)
    return image


class Image:
    def __init__(self, width, height, pixels):
        self.width, self.height, self.pixels = width, height, pixels  # rows of (r, g, b)

    @staticmethod
    def read_bmp(path):
        with open(path, "rb") as f:
            data = f.read()
        offset = struct.unpack_from("<I", data, 10)[0]
        width, height = struct.unpack_from("<ii", data, 18)
        bpp = struct.unpack_from("<H", data, 28)[0]
        if bpp not in (24, 32):
            raise RuntimeError(f"unsupported BMP depth {bpp}")
        step = bpp // 8
        stride = (width * step + 3) & ~3
        top_down = height < 0
        height = abs(height)
        pixels = []
        for y in range(height):
            row_index = y if top_down else height - 1 - y
            start = offset + row_index * stride
            row = data[start : start + width * step]
            pixels.append([(row[x + 2], row[x + 1], row[x]) for x in range(0, width * step, step)])
        return Image(width, height, pixels)

    def at(self, x, y):
        return self.pixels[y][x]

    def find(self, predicate):
        """Bounding boxes of 4-connected regions of matching pixels, largest first."""
        seen = set()
        boxes = []
        for y in range(self.height):
            row = self.pixels[y]
            for x in range(self.width):
                if (x, y) in seen or not predicate(row[x]):
                    continue
                stack = [(x, y)]
                seen.add((x, y))
                x0 = x1 = x
                y0 = y1 = y
                count = 0
                while stack:
                    cx, cy = stack.pop()
                    count += 1
                    x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if (
                            0 <= nx < self.width
                            and 0 <= ny < self.height
                            and (nx, ny) not in seen
                            and predicate(self.pixels[ny][nx])
                        ):
                            seen.add((nx, ny))
                            stack.append((nx, ny))
                boxes.append((count, (x0, y0, x1, y1)))
        boxes.sort(reverse=True)
        return [box for _, box in boxes]


def close_to(a, b, tolerance):
    return all(abs(x - y) <= tolerance for x, y in zip(a, b))


class Grid:
    """Maps cells to pixels, calibrated from two marker cells (top-left, bottom-right)."""

    def __init__(self, image, columns, rows):
        boxes = image.find(lambda p: p[0] > 200 and p[1] < 90 and p[2] > 200)
        if len(boxes) < 2:
            raise CheckFailed(f"calibration markers not found ({len(boxes)} regions)")
        first, last = sorted(boxes[:2], key=lambda b: (b[1], b[0]))
        self.x0, self.y0 = first[0], first[1]
        self.cell_w = (last[2] + 1 - first[0]) / columns
        self.cell_h = (last[3] + 1 - first[1]) / rows
        marker_w, marker_h = first[2] + 1 - first[0], first[3] + 1 - first[1]
        if abs(marker_w - self.cell_w) > 1.5 or abs(marker_h - self.cell_h) > 1.5:
            raise CheckFailed(
                f"calibration inconsistent: marker {marker_w}×{marker_h}, "
                f"grid cell {self.cell_w:.2f}×{self.cell_h:.2f}"
            )
        self.columns, self.rows = columns, rows

    def __str__(self):
        return f"origin ({self.x0},{self.y0}), cell {self.cell_w:.2f}×{self.cell_h:.2f} px"

    def background_sample(self, image, column, row):
        """The most common colour inside the cell (one pixel in from its edges): glyphs ink
        a minority of a cell's pixels, so this is its background."""
        left = int(round(self.x0 + column * self.cell_w))
        top = int(round(self.y0 + row * self.cell_h))
        counts = {}
        for y in range(top + 1, int(round(top + self.cell_h)) - 1):
            for x in range(left + 1, int(round(left + self.cell_w)) - 1):
                p = image.at(x, y)
                counts[p] = counts.get(p, 0) + 1
        return max(counts, key=counts.get)

    def ink_sample(self, image, column, row, background):
        """The pixel in the cell that differs most from the background: the glyph's colour."""
        left = int(self.x0 + column * self.cell_w)
        top = int(self.y0 + row * self.cell_h)
        best, best_distance = background, -1
        for y in range(top, int(top + self.cell_h)):
            for x in range(left, int(left + self.cell_w)):
                p = image.at(x, y)
                distance = sum(abs(a - b) for a, b in zip(p, background))
                if distance > best_distance:
                    best, best_distance = p, distance
        return best


# MARK: - ANSI dump parsing

XTERM_16 = [
    (0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0),
    (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
    (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0),
    (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
]  # fmt: skip


def xterm_256(n):
    if n < 16:
        return None  # profile-dependent; not checked
    if n < 232:
        n -= 16
        levels = [0, 95, 135, 175, 215, 255]
        return (levels[n // 36], levels[(n // 6) % 6], levels[n % 6])
    v = 8 + (n - 232) * 10
    return (v, v, v)


class Cell:
    __slots__ = ("char", "fg", "bg", "inverse")

    def __init__(self, char, fg, bg, inverse):
        self.char, self.fg, self.bg, self.inverse = char, fg, bg, inverse

    def colors(self, default_fg, default_bg):
        """(fg, bg) as RGB, or None where it isn't known (16-colour palette entries)."""
        fg = default_fg if self.fg == "default" else self.fg
        bg = default_bg if self.bg == "default" else self.bg
        return (bg, fg) if self.inverse else (fg, bg)


def parse_ansi(ansi, width, height):
    """Cell grid from FTXUI's ANSI output (SGR colours only; one line per row)."""
    rows = []
    for line in ansi.split("\n")[:height]:
        fg = bg = "default"
        inverse = False
        row = []
        i = 0
        while i < len(line):
            if line[i] == "\x1b":
                m = re.match(r"\x1b\[([0-9;]*)([A-Za-z])", line[i:])
                if not m:
                    i += 1
                    continue
                i += m.end()
                if m.group(2) != "m":
                    continue
                params = [int(p) if p else 0 for p in m.group(1).split(";")]
                j = 0
                while j < len(params):
                    p = params[j]
                    if p == 0:
                        fg = bg = "default"
                        inverse = False
                    elif p == 7:
                        inverse = True
                    elif p == 27:
                        inverse = False
                    elif p == 39:
                        fg = "default"
                    elif p == 49:
                        bg = "default"
                    elif p in (38, 48) and j + 1 < len(params):
                        if params[j + 1] == 2 and j + 4 < len(params):
                            color = tuple(params[j + 2 : j + 5])
                            j += 4
                        elif params[j + 1] == 5 and j + 2 < len(params):
                            color = xterm_256(params[j + 2])
                            j += 2
                        else:
                            color = None
                        if p == 38:
                            fg = color
                        else:
                            bg = color
                    elif 30 <= p <= 37 or 90 <= p <= 97:
                        fg = None
                    elif 40 <= p <= 47 or 100 <= p <= 107:
                        bg = None
                    j += 1
                continue
            char = line[i]
            i += 1
            if char in "\r":
                continue
            row.append(Cell(char, fg, bg, inverse))
        while len(row) < width:
            row.append(Cell(" ", "default", "default", False))
        rows.append(row[:width])
    while len(rows) < height:
        rows.append([Cell(" ", "default", "default", False) for _ in range(width)])
    return rows


# MARK: - A test window


def wait_until(predicate, timeout, what, interval=0.05):
    deadline = time.monotonic() + timeout
    while True:
        value = predicate()
        if value:
            return value
        if time.monotonic() > deadline:
            raise CheckFailed(f"timed out waiting for {what}")
        time.sleep(interval)


def normalized(text):
    lines = [line.rstrip() for line in text.replace("\r", "").split("\n")]
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


class Window:
    """A Terminal.app window with its own temporary profile, running one command.

    The profile runs `exec <dir>/run.sh`: it draws two calibration cells, waits for `go`, then
    execs the app. When the app exits cleanly the window closes (profile: close on exit)."""

    def __init__(self, scenario, directory):
        self.scenario = scenario
        self.dir = directory
        self.profile = f"{PROFILE_PREFIX}{os.getpid()}-{scenario.name}"
        self.window_id = None
        self.grid = None
        self.colors = PROFILE_COLORS[scenario.theme]
        self.dump_path = os.path.join(directory, "screen.json")
        self.shots = 0

    # Lifecycle

    def open(self):
        sc = self.scenario
        config = os.path.join(self.dir, "config.toml")
        with open(config, "w") as f:
            f.write(f'[ui]\ntheme = "{sc.theme}"\n')
        command = [sc.binary, *sc.arguments(config)]
        run = os.path.join(self.dir, "run.sh")
        with open(run, "w") as f:
            f.write(
                "#!/bin/sh\n"
                f"cd {shlex.quote(self.dir)}\n"
                "echo $$ > pid\n"
                # Hide the cursor, clear, mark the top-left and bottom-right cells.
                f"printf '\\033[?25l\\033[2J\\033[H\\033[48;2;255;0;255m \\033[0m"
                f"\\033[{sc.rows};{sc.columns}H\\033[48;2;255;0;255m \\033[0m'\n"
                "touch ready\n"
                "while [ ! -f go ]; do /bin/sleep 0.05; done\n"
                "printf '\\033[2J\\033[H'\n"
                f"VOCODER_DUMP_SCREEN={shlex.quote(self.dump_path)} "
                f"exec {' '.join(shlex.quote(c) for c in command)}\n"
            )
        os.chmod(run, 0o755)
        profile_file = os.path.join(self.dir, self.profile + ".terminal")
        with open(profile_file, "w") as f:
            f.write(profile_plist(self.profile, sc, f"exec {shlex.quote(run)}"))
        subprocess.run(["open", profile_file], check=True)
        self.window_id = wait_until(self._find_window, 15, f"window with profile {self.profile}")
        settings = f"settings set {as_string(self.profile)}"
        terminal(
            f"set background color of {settings} to {color16(self.colors['background'])}"
        )
        terminal(f"set normal text color of {settings} to {color16(self.colors['text'])}")
        terminal(f"set bold text color of {settings} to {color16(self.colors['text'])}")
        wait_until(lambda: os.path.exists(os.path.join(self.dir, "ready")), 20, "run.sh ready")
        time.sleep(0.3)
        image = self.screenshot("calibration")
        self.grid = Grid(image, sc.columns, sc.rows)
        bg = self.grid.background_sample(image, sc.columns // 2, sc.rows // 2)
        if not close_to(bg, self.colors["background"], BG_TOLERANCE):
            raise CheckFailed(
                f"profile background {bg} != {self.colors['background']} (colour management?)"
            )
        open(os.path.join(self.dir, "go"), "w").close()
        wait_until(
            lambda: (d := self.dump()) and d["width"] == sc.columns and d["height"] == sc.rows,
            20,
            f"first screen dump at {sc.columns}×{sc.rows}",
        )

    def _find_window(self):
        script = f"""
        tell application "Terminal"
          repeat with w in windows
            if (count of tabs of w) > 0 then
              if name of current settings of tab 1 of w is {as_string(self.profile)} then
                return id of w
              end if
            end if
          end repeat
          return ""
        end tell"""
        value = osascript(script)
        return int(value) if value else None

    def is_closed(self):
        try:
            return terminal(f"count of tabs of window id {self.window_id}") == "0"
        except RuntimeError:
            return True

    def pid(self):
        try:
            with open(os.path.join(self.dir, "pid")) as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            return None

    def close(self):
        """Ends the app (if still running), makes sure the window is gone, deletes the
        profile. Safe to call more than once."""
        if self.window_id is not None and not self.is_closed():
            pid = self.pid()
            for sig in (signal.SIGTERM, signal.SIGKILL):
                if pid is None:
                    break
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    break
                try:
                    wait_until(self.is_closed, 3, "window to close")
                    break
                except CheckFailed:
                    pass
            if not self.is_closed():
                terminal(f"close window id {self.window_id}")
        try:
            terminal(f"delete settings set {as_string(self.profile)}")
        except RuntimeError:
            pass

    # Reading

    def dump(self):
        try:
            with open(self.dump_path) as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def contents(self):
        return terminal(f"get contents of tab 1 of window id {self.window_id}")

    def settle(self, what, timeout=4.0):
        """Waits until the app's dump is stable and the window shows the same text."""
        last = {"seq": None, "since": time.monotonic()}

        def ready():
            dump = self.dump()
            if not dump:
                return None
            if dump["seq"] != last["seq"]:
                last["seq"], last["since"] = dump["seq"], time.monotonic()
                return None
            if time.monotonic() - last["since"] < 0.25:
                return None
            if normalized(self.contents()) != normalized(dump["text"]):
                return None
            return dump

        try:
            return wait_until(ready, timeout, what, interval=0.08)
        except CheckFailed:
            dump = self.dump() or {"text": ""}
            onscreen = self.contents()
            self.save_text("mismatch", onscreen, dump["text"])
            raise CheckFailed(
                f"{what}: window text != off-screen render\n"
                f"--- window\n{normalized(onscreen)}\n--- off-screen\n{normalized(dump['text'])}"
            )

    def save_text(self, label, onscreen, offscreen):
        base = os.path.join(self.dir, f"{self.shots:02d}-{label}")
        with open(base + ".window.txt", "w") as f:
            f.write(onscreen)
        with open(base + ".offscreen.txt", "w") as f:
            f.write(offscreen)

    def screenshot(self, label):
        self.shots += 1
        path = os.path.join(self.dir, f"{self.shots:02d}-{label}.png")
        self.last_shot = path
        return capture(self.window_id, path)

    # Input

    def keys(self, *strokes):
        """Sends keystrokes through System Events after making sure this window is frontmost.

        Strokes: "text" (typed), ("key", "p", ["control"]) (keystroke with modifiers), or
        ("code", 53) / ("code", 49, ["control"]) (key code)."""
        terminal("activate")
        terminal(f"set index of window id {self.window_id} to 1")
        time.sleep(0.15)
        front = osascript(
            'tell application "System Events" to get name of first process whose frontmost is true'
        )
        if front != "Terminal" or terminal("get id of front window") != str(self.window_id):
            raise CheckFailed(f"test window isn't frontmost ({front}); not sending keys")
        lines = []
        for stroke in strokes:
            if isinstance(stroke, str):
                lines.append(f"keystroke {as_string(stroke)}")
                continue
            kind, value, *rest = stroke
            modifiers = rest[0] if rest else []
            using = ""
            if modifiers:
                using = " using {" + ", ".join(f"{m} down" for m in modifiers) + "}"
            if kind == "key":
                lines.append(f"keystroke {as_string(value)}{using}")
            else:
                lines.append(f"key code {value}{using}")
            lines.append("delay 0.05")
        body = "\n".join(lines)
        osascript(f'tell application "System Events"\n{body}\nend tell')


def profile_plist(name, scenario, command):
    def boolean(value):
        return "<true/>" if value else "<false/>"

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>name</key><string>{name}</string>
<key>type</key><string>Window Settings</string>
<key>ProfileCurrentVersion</key><real>2.09</real>
<key>columnCount</key><integer>{scenario.columns}</integer>
<key>rowCount</key><integer>{scenario.rows}</integer>
<key>useOptionAsMetaKey</key>{boolean(scenario.meta)}
<key>shellExitAction</key><integer>0</integer>
<key>CommandString</key><string>{command}</string>
<key>RunCommandAsShell</key><false/>
<key>ShowActiveProcessInTitle</key><false/>
</dict></plist>
"""


# MARK: - Checks on a screen


class Screen:
    """A settled screen: the dump, its cell grid, and (lazily) a screenshot."""

    def __init__(self, window, label, dump):
        self.window, self.label, self.dump = window, label, dump
        self.cells = parse_ansi(dump["ansi"], dump["width"], dump["height"])
        self.image = window.screenshot(label)
        self.lines = dump["text"].split("\n")

    @property
    def text(self):
        return self.dump["text"]

    def default_colors(self):
        return self.window.colors["text"], self.window.colors["background"]

    def check_backgrounds(self):
        """Every cell's background in the screenshot matches what the app drew."""
        grid = self.window.grid
        default_fg, default_bg = self.default_colors()
        misses = []
        for y, row in enumerate(self.cells):
            for x, cell in enumerate(row):
                if cell.char in "█▀▄▌▐▔▁":  # glyphs that ink the sample points
                    continue
                _, expected = cell.colors(default_fg, default_bg)
                if expected is None:
                    continue
                got = grid.background_sample(self.image, x, y)
                if not close_to(got, expected, BG_TOLERANCE):
                    misses.append((x, y, expected, got))
        if len(misses) > BG_SLACK:
            sample = ", ".join(f"({x},{y}) want {e} got {g}" for x, y, e, g in misses[:6])
            raise CheckFailed(
                f"{self.label}: {len(misses)} cells with the wrong background: {sample}"
            )
        return len(misses)

    def cells_with_background(self, rgb, rows=None):
        default_fg, default_bg = self.default_colors()
        found = []
        for y, row in enumerate(self.cells):
            if rows is not None and y not in rows:
                continue
            for x, cell in enumerate(row):
                if cell.colors(default_fg, default_bg)[1] == rgb:
                    found.append((x, y))
        return found

    def check_pixel_background(self, cells, rgb, what):
        grid = self.window.grid
        for x, y in cells:
            got = grid.background_sample(self.image, x, y)
            if not close_to(got, rgb, BG_TOLERANCE):
                raise CheckFailed(f"{self.label}: {what} at ({x},{y}) is {got}, want {rgb}")

    def check_ink(self, x, y, what, tolerance=60):
        """The glyph at (x, y) is drawn in the foreground colour the app asked for."""
        default_fg, default_bg = self.default_colors()
        fg, bg = self.cells[y][x].colors(default_fg, default_bg)
        if fg is None or bg is None:
            return
        got = self.window.grid.ink_sample(self.image, x, y, bg)
        if not close_to(got, fg, tolerance):
            raise CheckFailed(f"{self.label}: {what} at ({x},{y}) drawn {got}, want {fg}")

    def find(self, needle):
        """(column, row) of the first occurrence of `needle` in the text, or None."""
        for y, line in enumerate(self.lines):
            column = column_of(line, needle)
            if column is not None:
                return column, y
        return None

    def selected_tab_text(self):
        cells = self.cells_with_background(SELECTION[self.window.scenario.theme], rows={0})
        return "".join(self.cells[y][x].char for x, y in cells).strip()

    def region_of(self, rgb):
        """Bounding box (x0, y0, x1, y1) of cells drawn with background `rgb`."""
        cells = self.cells_with_background(rgb)
        if not cells:
            return None
        xs, ys = [c[0] for c in cells], [c[1] for c in cells]
        return min(xs), min(ys), max(xs), max(ys)


def column_of(line, needle):
    """Cell column of `needle` in `line` (wide characters take two cells)."""
    import unicodedata

    index = line.find(needle)
    if index < 0:
        return None
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in line[:index])


# MARK: - Scenarios

CTRL = ["control"]
OPTION = ["option"]
ESC = ("code", 53)
ENTER = ("code", 36)
CTRL_SPACE = ("code", 49, CTRL)


class Scenario:
    def __init__(self, name, binary, base_args, theme, columns, rows, meta, steps):
        self.name, self.binary, self.base_args = name, binary, base_args
        self.theme, self.columns, self.rows, self.meta = theme, columns, rows, meta
        self.steps = steps

    def arguments(self, config):
        return [*self.base_args(config)]


def input_source_shortcut_enabled():
    """Whether macOS's "Select previous input source" (Ctrl-Space) is on (symbolic hotkey 60)
    and more than one input source is enabled."""
    try:
        out = subprocess.run(
            ["defaults", "read", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys"],
            capture_output=True, text=True, timeout=5,
        ).stdout  # fmt: skip
        m = re.search(r"\b60 =\s*\{\s*enabled = (\d)", out)
        return m is not None and m.group(1) == "1"
    except Exception:
        return False


def demo_steps(meta):
    def initial(w, report):
        s = Screen(w, "initial", w.settle("initial render"))
        s.check_backgrounds()
        if not s.selected_tab_text().startswith("1"):
            raise CheckFailed(f"selected tab should be Home, is {s.selected_tab_text()!r}")
        s.check_pixel_background(
            s.cells_with_background(SELECTION[w.scenario.theme], rows={0}),
            SELECTION[w.scenario.theme],
            "selected tab",
        )
        return s

    def leader(w, report):
        w.keys(CTRL_SPACE)
        try:
            s = Screen(w, "leader", w.settle("which-key popup", timeout=2.5))
        except CheckFailed:
            s = None
        if s is None or "Esc cancel" not in s.text:
            w.keys(ESC)
            w.settle("after leader")
            hint = (
                "macOS 'Select previous input source' is bound to Ctrl-Space"
                if input_source_shortcut_enabled()
                else "Ctrl-Space didn't reach the app"
            )
            raise Warning_(f"leader (Ctrl-Space) didn't open which-key: {hint}")
        s.check_backgrounds()
        w.keys(ESC)
        after = w.settle("which-key closed")
        if "Esc cancel" in after["text"]:
            raise CheckFailed("Esc didn't close which-key")

    def alt_digits(w, report):
        before = w.settle("before Alt-2")
        w.keys(("key", "2", OPTION))
        if meta:
            s = Screen(w, "alt-2", w.settle("Alt-2"))
            if not s.selected_tab_text().startswith("2"):
                raise CheckFailed(f"Alt-2 should select tab 2, selected {s.selected_tab_text()!r}")
            s.check_backgrounds()
            w.keys(("key", "1", OPTION))
            s = Screen(w, "alt-1", w.settle("Alt-1"))
            if not s.selected_tab_text().startswith("1"):
                raise CheckFailed(f"Alt-1 should select Home, selected {s.selected_tab_text()!r}")
        else:
            time.sleep(0.4)
            after = w.settle("Alt-2 without Option as Meta")
            if normalized(after["text"]) != normalized(before["text"]):
                raise CheckFailed("Alt-2 without Option as Meta changed the screen")

    def leader_digit(w, report):
        w.keys(CTRL_SPACE, "2")
        s = Screen(w, "leader-2", w.settle("<leader> 2"))
        if not s.selected_tab_text().startswith("2"):
            raise Warning_(
                f"<leader> 2 didn't select tab 2 ({s.selected_tab_text()!r}); Ctrl-Space lost?"
            )
        w.keys(CTRL_SPACE, "1")
        w.settle("<leader> 1")

    def palette_and_confirm(w, report):
        w.keys(("key", "p", CTRL))
        s = Screen(w, "palette", w.settle("palette"))
        if "Type a command" not in s.text:
            raise CheckFailed("Ctrl-P didn't open the palette")
        s.check_backgrounds()
        w.keys("publish")
        s = Screen(w, "palette-query", w.settle("palette query"))
        if "Publish the demo" not in s.text:
            raise CheckFailed("palette query 'publish' doesn't list 'Publish the demo'")
        w.keys(ENTER)
        s = Screen(w, "confirm", w.settle("confirm dialog"))
        position = s.find("Publish the demo")
        if position is None:
            raise CheckFailed("confirm dialog not shown")
        # Centred: the title's row is in the middle third of the screen.
        x, y = position
        rows, columns = w.scenario.rows, w.scenario.columns
        if not (rows // 4 <= y <= rows * 3 // 4):
            raise CheckFailed(f"confirm dialog title on row {y}, not centred in {rows} rows")
        s.check_backgrounds()
        focused = s.cells_with_background(FOCUS[w.scenario.theme])
        if focused:
            s.check_pixel_background(focused, FOCUS[w.scenario.theme], "focused button")
        w.keys(ESC)
        after = w.settle("confirm cancelled")
        if "Publish the demo" in after["text"]:
            raise CheckFailed("Esc didn't close the confirm dialog")

    def toast(w, report):
        # Tasks tab (3), then "Set issue status" from the palette → list picker → toast.
        w.keys(("key", "3", OPTION)) if meta else w.keys(CTRL_SPACE, "3")
        s = Screen(w, "tasks-tab", w.settle("tasks tab"))
        if not s.selected_tab_text().startswith("3"):
            # The keys didn't arrive (see the leader warning): switch through the palette.
            w.keys(("key", "p", CTRL), "switch to tab")
            w.settle("palette: switch to tab")
            w.keys(ENTER, "Tasks")
            w.settle("tab choices: Tasks")
            w.keys(ENTER)
            s = Screen(w, "tasks-tab-palette", w.settle("tasks tab via palette"))
            if not s.selected_tab_text().startswith("3"):
                raise CheckFailed(f"couldn't select the Tasks tab ({s.selected_tab_text()!r})")
        w.keys(("key", "p", CTRL), "issue status")
        w.settle("palette: issue status")
        w.keys(ENTER)
        s = Screen(w, "picker", w.settle("status picker"))
        s.check_backgrounds()
        w.keys(ENTER)
        s = Screen(w, "toast", w.settle("toast"))
        position = s.find(" is now ")
        if position is None:
            raise CheckFailed("no toast after setting a status")
        x, y = position
        if x < w.scenario.columns // 2 or y < w.scenario.rows // 2:
            raise CheckFailed(f"toast at ({x},{y}), expected bottom right")
        s.check_backgrounds()
        s.check_ink(x - 1, y, "toast text")

    def help_overlay(w, report):
        w.keys("?")
        s = Screen(w, "help", w.settle("help"))
        if "Command palette" not in s.text:
            raise CheckFailed("? didn't open help")
        s.check_backgrounds()
        w.keys(ESC)
        w.settle("help closed")

    def quit_(w, report):
        w.keys(("key", "c", CTRL))
        wait_until(w.is_closed, 5, "window to close after Ctrl-C (clean exit)")

    steps = [("initial render", initial), ("leader / which-key", leader)]
    steps.append(("Alt-digits" + ("" if meta else " (Option as Meta off)"), alt_digits))
    if not meta:
        steps.append(("<leader> digit", leader_digit))
    steps += [
        ("palette + confirm dialog", palette_and_confirm),
        ("list picker + toast", toast),
        ("help", help_overlay),
        ("quit", quit_),
    ]
    return steps


def gallery_steps():
    def theme_page(w, report):
        s = Screen(w, "theme-page", w.settle("gallery theme page"))
        s.check_backgrounds()
        # The role swatches: selection and focus colours appear as backgrounds.
        theme = w.scenario.theme
        for name, rgb in (("selection", SELECTION[theme]), ("focus", FOCUS[theme])):
            cells = s.cells_with_background(rgb)
            if not cells:
                raise CheckFailed(f"no {name} swatch on the theme page")
            s.check_pixel_background(cells[:8], rgb, f"{name} swatch")
        found = s.find(" sample ")
        if found:
            s.check_ink(found[0] + 1, found[1], "role sample text")

    def pages(w, report):
        # F-keys switch pages even while the form's text field has focus.
        f_keys = {1: 122, 2: 120, 3: 99, 4: 118, 5: 96, 6: 97}  # macOS key codes for F1…F6
        pages = ((2, "list"), (3, "table"), (4, "form"), (5, "layout"), (6, "markdown"))
        for page, label in pages:
            w.keys(("code", f_keys[page]))
            s = Screen(w, f"page-{label}", w.settle(f"gallery page {page} (F{page})"))
            s.check_backgrounds()
            if label == "markdown":
                # Styled text wrapped by the bridge's flow node, and the code block's background.
                if "Markdown-lite" not in s.text or "inline code" not in s.text:
                    raise CheckFailed("markdown page didn't render its sample")
                code = CODE_BACKGROUND[w.scenario.theme]
                cells = s.cells_with_background(code)
                if not cells:
                    raise CheckFailed("no code background on the markdown page")
                s.check_pixel_background(cells[:8], code, "code background")
        w.keys(("code", f_keys[1]))
        s = w.settle("back to page 1")
        if "Roles" not in s["text"]:
            raise CheckFailed("F1 didn't return to the theme page")

    def quit_(w, report):
        w.keys("q")
        wait_until(w.is_closed, 5, "window to close after q")

    return [("theme page", theme_page), ("pages", pages), ("quit", quit_)]


def scenarios(binary):
    def demo(config):
        return ["--demo", "--config", config]

    def gallery(theme):
        return lambda config: ["ui-gallery", "--theme", theme, "--still"]

    return [
        Scenario("demo-dark-80x24", binary, demo, "dark", 80, 24, True, demo_steps(True)),
        Scenario("demo-light-120x40", binary, demo, "light", 120, 40, False, demo_steps(False)),
        Scenario(
            "gallery-dark-80x24", binary, gallery("dark"), "dark", 80, 24, True, gallery_steps()
        ),
        Scenario(
            "gallery-light-120x40", binary, gallery("light"), "light", 120, 40, True,
            gallery_steps(),
        ),  # fmt: skip
    ]


# MARK: - Main


def remove_stale_profiles():
    names = terminal("get name of every settings set").split(", ")
    for name in names:
        if name.startswith(PROFILE_PREFIX):
            try:
                terminal(f"delete settings set {as_string(name)}")
            except RuntimeError:
                pass


def preflight():
    problems = []
    try:
        terminal("get name of default settings")
    except Exception as e:
        problems.append(f"Automation (Terminal): {e}")
    try:
        enabled = osascript('tell application "System Events" to get UI elements enabled')
        if enabled != "true":
            problems.append("Accessibility is off for this app (System Events keystrokes)")
    except Exception as e:
        problems.append(f"Automation (System Events): {e}")
    if problems:
        print("term-test: missing permissions (see README.md, 'Real-terminal checks'):")
        for p in problems:
            print("  - " + p)
        sys.exit(2)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("binary", nargs="?", default=os.path.join(ROOT, ".build/debug/vocoder"))
    parser.add_argument("-k", dest="filter", help="only scenarios whose name contains this")
    parser.add_argument("--keep", action="store_true", help="keep the window open on failure")
    args = parser.parse_args()
    binary = os.path.abspath(args.binary)
    if not os.access(binary, os.X_OK):
        sys.exit(f"term-test: no vocoder binary at {binary} (run `make build`)")

    preflight()
    remove_stale_profiles()
    results = os.path.join(ROOT, ".build", "term-test", time.strftime("%Y%m%d-%H%M%S"))
    os.makedirs(results)
    print(f"term-test: results in {results}")
    print("term-test: takes keyboard focus; don't type until it's done.\n")

    failures = warnings = 0
    selected = [s for s in scenarios(binary) if not args.filter or args.filter in s.name]
    interrupted = False
    for scenario in selected:
        directory = os.path.join(results, scenario.name)
        os.makedirs(directory)
        window = Window(scenario, directory)
        print(f"{scenario.name}")
        keep = False
        try:
            window.open()
            print(f"  calibrated: {window.grid}")
            for title, step in scenario.steps:
                notes = []
                try:
                    step(window, notes.append)
                    extra = f" ({'; '.join(notes)})" if notes else ""
                    print(f"  ok    {title}{extra}")
                except Warning_ as e:
                    warnings += 1
                    print(f"  warn  {title}: {e}")
                except CheckFailed as e:
                    failures += 1
                    shot = os.path.relpath(getattr(window, "last_shot", directory), ROOT)
                    print(f"  FAIL  {title}: {e}\n        screenshot: {shot}")
                    keep = args.keep
                    break
        except KeyboardInterrupt:
            interrupted = True
            print("  interrupted")
        except Exception as e:
            failures += 1
            print(f"  FAIL  setup: {e}")
            traceback.print_exc(file=sys.stdout)
        finally:
            if keep:
                print(f"  kept window {window.window_id} open (--keep); profile {window.profile}")
            else:
                window.close()
        if interrupted:
            break

    print(f"\nterm-test: {failures} failed, {warnings} warnings; results in {results}")
    sys.exit(1 if failures or interrupted else 0)


if __name__ == "__main__":
    main()
