// Runs the main run loop while a renderer owns the terminal, with the signal handling of
// ADR 0001. Shared by the development subcommands until the app's own loop exists (P1-07).
import Darwin
import Foundation
import VoCoderCore
import VoCoderUIBridge

@MainActor
final class TerminalRunLoop {
  private let renderer: VCRenderer
  private let log: Log
  private var signalSources: [DispatchSourceSignal] = []
  private var done = false
  /// While popped out, the child shares our process group: its Ctrl-C reaches us too.
  var ignoresInterrupt = false

  init(renderer: VCRenderer, log: Log) {
    self.renderer = renderer
    self.log = log
  }

  /// Starts the renderer and runs the main run loop until the TUI exits.
  func run() {
    for sig in [SIGINT, SIGTERM, SIGHUP] {
      signal(sig, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      source.setEventHandler { [self] in
        MainActor.assumeIsolated {
          if sig == SIGINT && self.ignoresInterrupt { return }
          self.log.info("signal \(sig): stopping")
          self.renderer.stop()
        }
      }
      source.resume()
      signalSources.append(source)
    }
    renderer.onExit = { [self] in
      DispatchQueue.main.async { MainActor.assumeIsolated { self.done = true } }
    }
    renderer.start()
    while !done {
      _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }
  }
}
