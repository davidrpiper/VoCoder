// P0-01 spike app: tab bar, a stateful input, a clock updated from a background task, an event
// log, and off-screen rendering. Swift 6 language mode, no C++ interop.
import Foundation
import Synchronization
import VCBridge

let tabs = ["Home", "Input", "Keys"]

struct AppState: Sendable {
  var tab = 0
  var ticks = 0
  var inputFocused = false
  var inputValue = ""
  var keyLog: [String] = []
  var setRootCalls = 0
  var size = "?"
}

let state = Mutex(AppState())
let renderer = VCRenderer()
let startTime = Date()
let terminalName = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "unknown"
let logURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  .appending(path: "ftxui-spike-\(terminalName).log")
let logLock = Mutex(())

/// Never print while the TUI runs: diagnostics go to a file.
func log(_ line: String) {
  logLock.withLock { _ in
    let stamped = String(format: "%8.3f ", Date().timeIntervalSince(startTime)) + line + "\n"
    if let handle = try? FileHandle(forWritingTo: logURL) {
      handle.seekToEndOfFile()
      handle.write(Data(stamped.utf8))
      try? handle.close()
    } else {
      try? Data(stamped.utf8).write(to: logURL)
    }
  }
}

func tree(_ s: AppState) -> VCNode {
  var tabCells: [VCNode] = []
  for (i, name) in tabs.enumerated() {
    let cell = VCNode.text(" \(i + 1):\(name) ")
    tabCells.append(i == s.tab ? cell.styled([.inverted, .bold]) : cell.styled(.dim))
  }
  tabCells.append(VCNode.filler())
  tabCells.append(VCNode.text("tick \(s.ticks) ").color(.cyan))

  let body: VCNode
  switch s.tab {
  case 0:
    body = VCNode.vbox([
      VCNode.text("VoCoder FTXUI bridge spike").styled(.bold),
      VCNode.text("Alt-1..3 / Tab / h,l switch tabs · q or Ctrl-C quits"),
      VCNode.text("Background ticks: \(s.ticks) (setRoot from a detached task)"),
      VCNode.text("Terminal size: \(s.size)"),
      VCNode.text("Unicode: café · 日本語 · emoji 🎙️ · box ─│"),
    ])
  case 1:
    body = VCNode.vbox([
      VCNode.text(s.inputFocused ? "Editing (Esc to leave)" : "Press Enter or i to edit"),
      VCNode.hbox([
        VCNode.text("Name: "),
        VCNode.input(withId: "name", placeholder: "type here").styled(.flex),
      ]).bordered(),
      VCNode.text("Swift sees: \"\(s.inputValue)\""),
    ])
  default:
    body = VCNode.vbox(
      [VCNode.text("Last keys (name [raw bytes]) — try Ctrl-Space, Alt-1, Ctrl-I:").styled(.bold)]
        + s.keyLog.suffix(15).map { VCNode.text($0) })
  }

  return VCNode.vbox([
    VCNode.hbox(tabCells),
    VCNode.separator(),
    body.styled(.flex),
    VCNode.separator(),
    VCNode.text("setRoot calls: \(s.setRootCalls) · frames: \(renderer.framesDrawn)").styled(.dim),
  ]).bordered()
}

/// Thread-safe: called from the main actor and from the background ticker.
func render() {
  let node = state.withLock { s in
    s.setRootCalls += 1
    return tree(s)
  }
  renderer.setRoot(node)
}

@MainActor
func handle(_ event: VCEvent) {
  log(event.description)
  switch event.kind {
  case .resize:
    state.withLock { $0.size = "\(event.width)x\(event.height)" }
  case .widgetChanged:
    state.withLock { $0.inputValue = event.value ?? "" }
  case .key:
    var quit = false
    state.withLock { s in
      s.keyLog.append("\(event.key) [\(event.rawHex)]")
      let key = event.key
      if s.inputFocused {
        if key == "Esc" { s.inputFocused = false }
        return
      }
      switch key {
      case "Alt-1", "Alt-2", "Alt-3": s.tab = Int(key.suffix(1))! - 1
      case "Tab", "l", "ArrowRight": s.tab = (s.tab + 1) % tabs.count
      case "Shift-Tab", "h", "ArrowLeft": s.tab = (s.tab + tabs.count - 1) % tabs.count
      case "Enter" where s.tab == 1, "i" where s.tab == 1: s.inputFocused = true
      case "q", "Ctrl-c": quit = true
      default: break
      }
    }
    if quit {
      renderer.stop()
      return
    }
    renderer.setFocusedWidget(state.withLock { $0.inputFocused } ? "name" : nil)
  @unknown default:
    break
  }
  render()
}

func snapshot() -> Int32 {
  renderer.setValue("héllo 日本", forWidget: "name")
  var outputs: [String] = []
  for tab in [0, 1, 2] {
    state.withLock {
      $0.tab = tab
      $0.ticks = 42
      $0.size = "80x24"
      $0.inputValue = "héllo 日本"
    }
    render()
    let a = renderer.renderToString(width: 60, height: 12, ansi: false)
    let b = renderer.renderToString(width: 60, height: 12, ansi: false)
    print("--- tab \(tab) (stable: \(a == b)) ---")
    print(a, terminator: "")
    outputs.append(a)
  }
  print("--- ansi bytes for tab 2: \(renderer.renderToString(width: 60, height: 12, ansi: true).utf8.count)")
  return 0
}

let args = CommandLine.arguments.dropFirst()
if args.contains("--snapshot") {
  exit(snapshot())
}

let stress = args.contains("--stress")
renderer.onEvent = { event in
  Task { @MainActor in handle(event) }
}
renderer.onExit = {
  DispatchQueue.main.async {
    let s = state.withLock { $0 }
    print("exited cleanly · setRoot calls \(s.setRootCalls) · frames drawn \(renderer.framesDrawn) · \(renderer.latencySummary)")
    exit(0)
  }
}

// FTXUI handles SIGINT/SIGTERM/SIGHUP during the loop: it restores the terminal, exits the loop,
// then restores the previous handler and re-raises. With SIG_IGN as the previous handler the
// re-raise is harmless, the loop thread returns and onExit runs; the dispatch sources (kqueue
// sees ignored signals) cover signals arriving outside the loop.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
  signal(sig, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
  source.setEventHandler {
    log("signal \(sig)")
    renderer.stop()
  }
  source.resume()
  signalSources.append(source)
}

try? FileManager.default.removeItem(at: logURL)
log("start TERM=\(ProcessInfo.processInfo.environment["TERM"] ?? "") TERM_PROGRAM=\(ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "")")
render()
renderer.start()

// Background ticker: mutates state and calls setRoot off the main thread.
Task.detached {
  while true {
    try? await Task.sleep(for: .milliseconds(100))
    state.withLock { $0.ticks += 1 }
    render()
  }
}

if stress {
  // Hammer setRoot from several threads to check thread-safety and coalescing.
  for _ in 0..<4 {
    Thread.detachNewThread {
      for _ in 0..<20_000 { render() }
      log("stress thread done")
    }
  }
}

dispatchMain()
