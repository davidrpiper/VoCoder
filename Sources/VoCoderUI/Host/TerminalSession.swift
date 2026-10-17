// Runs the TUI on the terminal with the signal handling of ADR 0001, and pops out to
// interactive programs (`claude --resume`, `$EDITOR`, a shell) and back. Used by the app and the
// development subcommands.
import Darwin
import Foundation
import VoCoderCore
import VoCoderUIBridge

@MainActor
public final class TerminalSession {
  public let renderer: VCRenderer
  /// While popped out the child shares our process group: its Ctrl-C reaches us too and is
  /// ignored.
  public private(set) var isPoppedOut = false
  private let log: Log
  private var signalSources: [DispatchSourceSignal] = []
  private var done = false

  public init(renderer: VCRenderer, log: Log = Log(category: "terminal")) {
    self.renderer = renderer
    self.log = log
  }

  /// Starts the renderer and runs the main run loop until the TUI exits. SIGINT, SIGTERM and
  /// SIGHUP stop it gracefully (the terminal is restored by the renderer).
  public func run() {
    for sig in [SIGINT, SIGTERM, SIGHUP] {
      signal(sig, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
      source.setEventHandler { [self] in
        MainActor.assumeIsolated {
          if sig == SIGINT && self.isPoppedOut { return }
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
    for source in signalSources { source.cancel() }
    signalSources = []
  }

  /// Hands the terminal to `program` (looked up on `PATH` unless it contains a "/") with
  /// `arguments`, waits for it to exit, then takes the terminal back and redraws. `banner` is
  /// printed first. Returns the wait status, or -1 if it couldn't be started.
  public func popOut(
    _ program: String, arguments: [String] = [], directory: URL? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment, banner: String? = nil
  ) async -> Int32 {
    isPoppedOut = true
    log.info("pop-out: \(program)")
    let status = await withCheckedContinuation { continuation in
      renderer.runSuspended {
        if let banner { print(banner) }
        let status = Self.spawnAndWait(
          program, arguments: arguments, directory: directory?.path, environment: environment)
        continuation.resume(returning: status)
      }
    }
    isPoppedOut = false
    log.info("pop-out: \(program) exited with \(status)")
    return status
  }

  /// Runs the program attached to the terminal and waits. Not `Process`: it starts the child in
  /// a new process group, which isn't the terminal's foreground group, so Ctrl-C and tty reads
  /// fail. posix_spawn keeps our group; SETSIGDEF undoes our SIG_IGN (inherited across exec).
  private nonisolated static func spawnAndWait(
    _ program: String, arguments: [String], directory: String?, environment: [String: String]
  ) -> Int32 {
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    var defaults = sigset_t()
    sigemptyset(&defaults)
    for sig in [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGTSTP] { sigaddset(&defaults, sig) }
    posix_spawnattr_setsigdefault(&attributes, &defaults)
    var mask = sigset_t()
    sigemptyset(&mask)
    posix_spawnattr_setsigmask(&attributes, &mask)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    if let directory { posix_spawn_file_actions_addchdir(&actions, directory) }

    let argv: [UnsafeMutablePointer<CChar>?] = ([program] + arguments).map { strdup($0) } + [nil]
    let envp: [UnsafeMutablePointer<CChar>?] =
      environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { for pointer in argv + envp { free(pointer) } }
    var pid: pid_t = 0
    guard posix_spawnp(&pid, program, &actions, &attributes, argv, envp) == 0 else {
      return -1
    }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    return status
  }
}
