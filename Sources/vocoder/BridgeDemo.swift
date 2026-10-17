// `vocoder bridge-demo` (hidden): exercises the UI bridge live and is the target of
// `scripts/bridge-pty-test.py`. Talks to VoCoderUIBridge directly, which only this demo does;
// the app goes through VoCoderUI (it shares the `TerminalSession`).
import ArgumentParser
import Darwin
import Foundation
import VoCoderCore
import VoCoderUI
import VoCoderUIBridge

struct BridgeDemoCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bridge-demo",
    abstract: "Interactive UI bridge demo (development).",
    shouldDisplay: false
  )

  @Flag(help: "Report mouse events.") var mouse = false
  @Flag(help: "No clock or spinner, so the screen only changes on input.") var still = false
  @Option(help: "After each resize, write the off-screen render of the screen to this file.")
  var dumpOffscreen: String?
  @Option(help: "Crash with a Swift runtime trap after this many seconds.") var crashAfter: Double?

  func run() throws {
    Log.bootstrap(sink: FileLogSink(directory: Log.defaultDirectory))
    MainActor.assumeIsolated {
      BridgeDemo(
        mouse: mouse, still: still, dumpPath: dumpOffscreen, crashAfter: crashAfter
      ).run()
    }
  }
}

@MainActor
final class BridgeDemo {
  private let renderer = VCRenderer()
  private let log = Log(category: "bridge-demo")
  private let still: Bool
  private let dumpPath: String?
  private let crashAfter: Double?

  private let tabs = ["Home", "Input", "List", "Widgets", "Keys"]
  private var tab = 0
  private var leaderPending = false
  private var ticks = 0
  private var size = (width: 0, height: 0)
  private var selectedRow = 0
  private var submitted = ""
  private var keyLog: [String] = []
  private lazy var session = TerminalSession(renderer: renderer, log: log)
  private var timers: [Timer] = []

  init(mouse: Bool, still: Bool, dumpPath: String?, crashAfter: Double?) {
    renderer.trackMouse = mouse
    self.still = still
    self.dumpPath = dumpPath
    self.crashAfter = crashAfter
  }

  /// Runs the main run loop until the TUI exits.
  func run() {
    renderer.onEvent = { [self] event in
      DispatchQueue.main.async { MainActor.assumeIsolated { self.handle(event) } }
    }
    update()
    log.info("bridge demo started")
    if !still {
      schedule(every: 0.1) { demo in
        demo.ticks += 1
        demo.update()
      }
    }
    if let crashAfter {
      schedule(after: crashAfter) { _ in fatalError("bridge-demo: deliberate crash") }
    }
    session.run()
    for timer in timers { timer.invalidate() }
    log.info("bridge demo exited cleanly")
  }

  // MARK: Events

  private func handle(_ event: VCEvent) {
    switch event.kind {
    case .resize:
      size = (event.width, event.height)
      dumpOffscreenSoon()
    case .widgetChanged:
      break
    case .widgetSubmitted:
      submitted = "\(event.widgetId ?? "?"): \(event.stringValue ?? String(event.integerValue))"
      renderer.focusedWidget = nil
    case .mouse:
      record(
        "mouse \(event.mouseButton.rawValue)/\(event.mouseMotion.rawValue) at \(event.x),\(event.y)"
      )
    case .key:
      record("\(event.key)  [\(event.rawHex)]")
      handleKey(event.key)
    @unknown default:
      break
    }
    update()
  }

  private func handleKey(_ key: String) {
    if leaderPending {
      leaderPending = false
      if let digit = Int(key), (1...tabs.count).contains(digit) { tab = digit - 1 }
      return
    }
    if key == "Ctrl-Space" {
      leaderPending = true
      return
    }
    if renderer.focusedWidget != nil {
      if key == "Esc" || key == "Tab" { renderer.focusedWidget = nil }
      return
    }
    switch key {
    case "q", "Ctrl-c": renderer.stop()
    case "Tab": tab = (tab + 1) % tabs.count
    case "Shift-Tab": tab = (tab + tabs.count - 1) % tabs.count
    case let alt where alt.hasPrefix("Alt-"):
      if let digit = Int(alt.dropFirst(4)), (1...tabs.count).contains(digit) { tab = digit - 1 }
    case "p": popOut()
    case "i" where tab == 1: renderer.focusedWidget = "name"
    case "n" where tab == 1: renderer.focusedWidget = "notes"
    case "f" where tab == 2: renderer.focusedWidget = "fruit"
    case "j", "ArrowDown": if tab == 2 { selectedRow = min(99, selectedRow + 1) }
    case "k", "ArrowUp": if tab == 2 { selectedRow = max(0, selectedRow - 1) }
    default: break
    }
  }

  private func record(_ line: String) {
    keyLog.append(line)
    if keyLog.count > 500 { keyLog.removeFirst(keyLog.count - 500) }
  }

  // MARK: Pop-out

  private func popOut() {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    Task {
      let status = await session.popOut(
        shell, banner: "bridge-demo: popped out to \(shell). Exit the shell to return.")
      record("pop-out: \(shell) exited with \(status)")
      update()
    }
  }

  // MARK: Off-screen dump (for the pty test)

  private func dumpOffscreenSoon() {
    guard let dumpPath else { return }
    schedule(after: 0.5) { demo in
      let text = demo.renderer.renderToString(
        width: demo.size.width, height: demo.size.height, ansi: false)
      try? text.write(toFile: dumpPath, atomically: true, encoding: .utf8)
    }
  }

  // MARK: Timers

  private func schedule(
    every interval: TimeInterval, _ body: @escaping @MainActor (BridgeDemo) -> Void
  ) {
    timers.append(
      Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [self] _ in
        MainActor.assumeIsolated { body(self) }
      })
  }

  private func schedule(
    after delay: TimeInterval, _ body: @escaping @MainActor (BridgeDemo) -> Void
  ) {
    timers.append(
      Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [self] _ in
        MainActor.assumeIsolated { body(self) }
      })
  }

  // MARK: View

  private func update() {
    renderer.setRoot(tree())
  }

  private func tree() -> VCNode {
    let titles = tabs.enumerated().map { "\($0.offset + 1):\($0.element)" }
    let header = VCNode.hbox([
      .tabBar(titles, selected: tab),
      .filler(),
      VCNode.text(still ? "" : "tick \(ticks) ").foreground(.named(.cyan)),
    ])
    let status =
      leaderPending
      ? "Ctrl-Space … 1-\(tabs.count) jump to tab"
      : "q/Ctrl-C quit · Tab/Shift-Tab or Ctrl-Space n switch tabs · p pop out to $SHELL"
    return .vbox([
      header,
      .separator(),
      body().flex(.both),
      .separator(),
      VCNode.text(status).styled(.dim),
    ])
  }

  private func body() -> VCNode {
    switch tab {
    case 0: home()
    case 1: inputs()
    case 2: lists()
    case 3: widgets()
    default: keys()
    }
  }

  private func home() -> VCNode {
    let terminal = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "?"
    let palette: [VCNode] = (0..<16).map { i in
      VCNode.text("  ").background(.named(VCNamedColor(rawValue: i) ?? .black))
    }
    let gradient: [VCNode] = (0..<32).map { i in
      VCNode.text(" ").background(.rgb(UInt8(i * 8), UInt8(255 - i * 8), 128))
    }
    let lines: [VCNode] = [
      VCNode.text("VoCoder UI bridge demo").styled(.bold),
      VCNode.text("Terminal: \(terminal)"),
      VCNode.text("Size: \(size.width)×\(size.height) · frames drawn: \(renderer.framesDrawn)"),
      VCNode.text("Mouse reporting: \(renderer.trackMouse ? "on" : "off")"),
      VCNode.text("Unicode: café · 日本語 · box ─│┌┐ · emoji 🎤"),
      VCNode.text(""),
      VCNode.text("Colours:").styled(.bold),
      VCNode.hbox(palette),
      VCNode.hbox(gradient),
      VCNode.text("bold").styled(.bold),
      VCNode.text("dim").styled(.dim),
      VCNode.text("italic underlined").styled([.italic, .underlined]),
    ]
    return VCNode.vbox(lines)
  }

  private func inputs() -> VCNode {
    let focused = renderer.focusedWidget
    return .vbox([
      .text(
        focused == nil
          ? "i edits the name, n edits the notes; Esc or Tab leaves the field"
          : "Editing \(focused!) — Esc/Tab to leave, Enter submits the name"),
      VCNode.input(id: "name", placeholder: "your name", multiline: false)
        .bordered(style: focused == "name" ? .heavy : .rounded, title: "Name"),
      VCNode.input(id: "notes", placeholder: "multi-line notes", multiline: true)
        .height(.equal, 4)
        .bordered(style: focused == "notes" ? .heavy : .rounded, title: "Notes"),
      .text("Swift sees name: \"\(renderer.stringValue(forWidget: "name") ?? "")\""),
      .text("Last submitted: \(submitted)"),
    ])
  }

  private func lists() -> VCNode {
    let fruits = ["Apple", "Banana", "Cherry", "Damson", "Elderberry", "Fig", "Grape"]
    let rows = (0..<100).map { i -> VCNode in
      let row = VCNode.text(String(format: " row %03d ", i))
      return i == selectedRow ? row.styled(.inverted).focusMarker() : row
    }
    return .hbox([
      VCNode.menu(id: "fruit", entries: fruits)
        .bordered(style: .rounded, title: "menu (f focuses)")
        .width(.equal, 22),
      VCNode.scrollFrame(id: "rows", followingEnd: false, child: .vbox(rows))
        .bordered(style: .rounded, title: "scroll (j/k)")
        .flex(.both),
    ])
  }

  private func widgets() -> VCNode {
    let progress = Float(ticks % 100) / 100
    return .vbox([
      .table(
        [
          [.text("Module"), .text("State"), .text("Notes")],
          [.text("Git"), VCNode.text("ok").foreground(.named(.green)), .text("clean")],
          [.text("Claude Code"), VCNode.text("busy").foreground(.named(.yellow)), .text("turn 3")],
          [.text("Linear"), VCNode.text("off").styled(.dim)],
        ], options: [.header, .border, .columnSeparators]),
      .hbox([.text("Gauge "), VCNode.gauge(progress, axis: .horizontal).width(.equal, 30)]),
      .hbox([.text("Spinner "), .spinner(charset: 15, frame: ticks)]),
      VCNode.paragraph(
        "This paragraph wraps to the width of the terminal. Resize the window and watch it "
          + "reflow; the node tree is rebuilt in Swift and laid out by FTXUI."
      ).bordered(style: .light, title: "paragraph"),
    ])
  }

  private func keys() -> VCNode {
    .vbox([
      VCNode.text("Last keys (try Ctrl-Space, Alt-1, Ctrl-I, F5, arrows):").styled(.bold),
      VCNode.scrollFrame(
        id: "keys", followingEnd: true, child: .vbox(keyLog.map { VCNode.text($0) })
      ).flex(.both),
    ])
  }
}
