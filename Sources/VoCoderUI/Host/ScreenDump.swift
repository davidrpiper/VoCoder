// **Testing only.** Writes the off-screen render of a host's screen to a file whenever it
// changes, so `make term-test` can compare a real terminal window with what the app drew
// (`$VOCODER_DUMP_SCREEN`, read by `vocoder` and `vocoder ui-gallery`; an environment variable
// because a subcommand can't share an option name with the root command).
import Foundation
import VoCoderCore
import VoCoderUIBridge

@MainActor
public final class ScreenDump {
  private let host: UIHost
  private let url: URL
  private let interval: TimeInterval
  private let size: @MainActor () -> (width: Int, height: Int)
  private var timer: Timer?
  private var last: (text: String, ansi: String)?
  private var sequence = 0
  private let log = Log(category: "ui")

  public convenience init(host: UIHost, path: String, interval: TimeInterval = 0.1) {
    self.init(host: host, path: path, interval: interval) { [unowned host] in host.size }
  }

  /// `size` replaces the host's terminal size (tests).
  init(
    host: UIHost, path: String, interval: TimeInterval = 0.1,
    size: @escaping @MainActor () -> (width: Int, height: Int)
  ) {
    self.host = host
    self.url = URL(fileURLWithPath: path)
    self.interval = interval
    self.size = size
  }

  /// The dump `$VOCODER_DUMP_SCREEN` asks for, if any.
  public static func fromEnvironment(
    host: UIHost, environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> ScreenDump? {
    guard let path = environment["VOCODER_DUMP_SCREEN"], !path.isEmpty else { return nil }
    return ScreenDump(host: host, path: path)
  }

  /// Polls on the main run loop (cheap; only used under test).
  public func start() {
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.dumpIfChanged() }
    }
  }

  public func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// One JSON object: `seq`, `width`, `height`, `text` (plain, trailing spaces trimmed) and
  /// `ansi` (at the renderer's colour depth, like the terminal gets it). Written atomically.
  func dumpIfChanged() {
    let (width, height) = size()
    guard width > 0, height > 0 else { return }
    let renderer = host.renderer
    let text = renderer.renderToString(width: width, height: height, ansi: false)
    let ansi = renderer.renderToString(
      width: width, height: height, colorDepth: VCRenderer.colorDepth)
    guard last.map({ $0.text != text || $0.ansi != ansi }) ?? true else { return }
    last = (text, ansi)
    sequence += 1
    let object: [String: Any] = [
      "seq": sequence, "width": width, "height": height, "text": text, "ansi": ansi,
    ]
    do {
      let data = try JSONSerialization.data(withJSONObject: object)
      try data.write(to: url, options: .atomic)
    } catch {
      log.error("screen dump failed: \(error)")
    }
  }
}
