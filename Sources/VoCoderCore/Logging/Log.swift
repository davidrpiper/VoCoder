import Foundation
import Synchronization
import os

/// The logging facility. Every entry goes to the unified log (`os.Logger`, subsystem
/// `dev.vocoder`) and, once `Log.bootstrap` has run, to a rotating file
/// (`~/Library/Logs/VoCoder/vocoder.log`; `make logs` tails it).
///
/// Never write to stdout/stderr while the TUI runs; log instead. Never log secrets.
public struct Log: Sendable {
  public static let subsystem = "dev.vocoder"

  /// `~/Library/Logs/VoCoder`.
  public static var defaultDirectory: URL {
    URL.libraryDirectory.appending(path: "Logs/VoCoder", directoryHint: .isDirectory)
  }

  private static let sharedSink = Mutex<FileLogSink?>(nil)

  /// Installs the file sink used by all loggers. Call once at startup.
  public static func bootstrap(sink: FileLogSink?) {
    sharedSink.withLock { $0 = sink }
  }

  public let category: String
  private let osLogger: os.Logger
  private let sink: FileLogSink?
  private let usesSharedSink: Bool

  /// A logger writing to the shared sink installed by `bootstrap`.
  public init(category: String) {
    self.category = category
    self.osLogger = os.Logger(subsystem: Log.subsystem, category: category)
    self.sink = nil
    self.usesSharedSink = true
  }

  /// A logger writing to a specific sink (tests).
  public init(category: String, sink: FileLogSink?) {
    self.category = category
    self.osLogger = os.Logger(subsystem: Log.subsystem, category: category)
    self.sink = sink
    self.usesSharedSink = false
  }

  public func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
    let text = message()
    osLogger.log(level: level.osLogType, "\(text, privacy: .public)")
    let target = usesSharedSink ? Log.sharedSink.withLock { $0 } : sink
    target?.write(level: level, category: category, message: text)
  }

  public func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
  public func info(_ message: @autoclosure () -> String) { log(.info, message()) }
  public func notice(_ message: @autoclosure () -> String) { log(.notice, message()) }
  public func error(_ message: @autoclosure () -> String) { log(.error, message()) }
  public func fault(_ message: @autoclosure () -> String) { log(.fault, message()) }
}

extension LogLevel {
  var osLogType: OSLogType {
    switch self {
    case .debug: .debug
    case .info: .info
    case .notice: .default
    case .error: .error
    case .fault: .fault
    }
  }
}
