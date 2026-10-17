import Synchronization
import Testing
import VoCoderUIBridge

@Suite struct EventTests {
  let renderer = VCRenderer()

  @Test func keysArriveWithNamesAndRawBytes() {
    let recorder = EventRecorder(renderer)
    renderer.injectInput("a")
    renderer.injectInput("\u{0}")
    renderer.injectInput("\u{1B}1")
    renderer.injectInput("\u{1B}[105;5u")  // Ghostty's Ctrl-I
    renderer.injectInput("\u{1B}OA")  // application-mode ArrowUp
    renderer.injectInput("\u{10}")  // Ctrl-P
    #expect(recorder.keys == ["a", "Ctrl-Space", "Alt-1", "Ctrl-i", "ArrowUp", "Ctrl-p"])
    #expect(recorder.events[3].rawHex == "1b 5b 31 30 35 3b 35 75")
    #expect(recorder.events[4].rawHex == "1b 5b 41")  // FTXUI normalises SS3 arrows
  }

  @Test func severalKeysInOneChunk() {
    let recorder = EventRecorder(renderer)
    renderer.injectInput("jk\u{1B}[Bq")
    #expect(recorder.keys == ["j", "k", "ArrowDown", "q"])
  }

  @Test func loneEscapeIsFlushed() {
    let recorder = EventRecorder(renderer)
    renderer.injectInput("\u{1B}")
    #expect(recorder.keys == ["Esc"])
  }

  @Test func mouseIgnoredUnlessTracking() {
    let recorder = EventRecorder(renderer)
    let click = "\u{1B}[<0;5;3M"  // SGR: left press at column 5, row 3 (1-based)
    renderer.injectInput(click)
    #expect(recorder.events.isEmpty)

    renderer.trackMouse = true
    renderer.injectInput(click)
    renderer.injectInput("\u{1B}[<65;1;1M")  // wheel down
    let mouse = recorder.events
    #expect(mouse.count == 2)
    #expect(mouse.first?.kind == .mouse)
    #expect(mouse.first?.mouseButton == .left)
    #expect(mouse.first?.mouseMotion == .pressed)
    #expect(mouse.first?.x == 4)
    #expect(mouse.first?.y == 2)
    #expect(mouse.last?.mouseButton == .wheelDown)
  }

  @Test func noCallbackIsFine() {
    renderer.injectInput("abc\u{1B}[A")
  }
}

@Suite struct RendererLifecycleTests {
  @Test func idleRenderer() {
    let renderer = VCRenderer()
    #expect(!renderer.isRunning)
    #expect(renderer.framesDrawn == 0)
    #expect(!renderer.trackMouse)
    #expect(renderer.focusedWidget == nil)
    renderer.focusedWidget = "x"
    #expect(renderer.focusedWidget == "x")
    renderer.focusedWidget = nil
    #expect(renderer.focusedWidget == nil)
    renderer.stop()  // no-op when not running
  }

  @Test func runSuspendedRunsDirectlyWhenNotRunning() {
    let called = Mutex(false)
    VCRenderer().runSuspended { called.withLock { $0 = true } }
    #expect(called.withLock { $0 })
  }

  @Test func renderWithoutRoot() {
    #expect(VCRenderer().renderToString(width: 3, height: 2, ansi: false) == lines("", ""))
  }
}
