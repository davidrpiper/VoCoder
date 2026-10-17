import Foundation
import Synchronization

/// Appends log lines to `<directory>/<baseName>.log`, rotating by size to
/// `<baseName>.1.log` … `<baseName>.<maxFiles - 1>.log` (oldest highest).
///
/// Thread-safe; writes are synchronous so nothing is lost on a crash or exit.
public final class FileLogSink: Sendable {
  public let directory: URL
  public let baseName: String
  public let maxBytes: Int
  public let maxFiles: Int
  public let minimumLevel: LogLevel

  private struct State {
    var handle: FileHandle?
    var size = 0
  }
  private let state = Mutex(State())

  /// Local time with offset, e.g. `2026-10-17T16:02:51.223+11:00`.
  private static let timestampStyle = Date.ISO8601FormatStyle(
    includingFractionalSeconds: true,
    timeZone: .current
  )

  public init(
    directory: URL,
    baseName: String = "vocoder",
    maxBytes: Int = 5 * 1024 * 1024,
    maxFiles: Int = 3,
    minimumLevel: LogLevel = .info
  ) {
    precondition(maxBytes > 0 && maxFiles >= 1)
    self.directory = directory
    self.baseName = baseName
    self.maxBytes = maxBytes
    self.maxFiles = maxFiles
    self.minimumLevel = minimumLevel
  }

  deinit {
    state.withLock { try? $0.handle?.close() }
  }

  /// The file currently written to.
  public var currentFile: URL { file(index: 0) }

  func file(index: Int) -> URL {
    directory.appending(path: index == 0 ? "\(baseName).log" : "\(baseName).\(index).log")
  }

  public func write(level: LogLevel, category: String, message: String, date: Date = .now) {
    guard level >= minimumLevel else { return }
    let timestamp = date.formatted(Self.timestampStyle)
    let line = "\(timestamp) \(level.label) [\(category)] \(message)\n"
    let data = Data(line.utf8)
    state.withLock { state in
      if state.handle != nil, state.size > 0, state.size + data.count > maxBytes {
        rotate(&state)
      }
      if state.handle == nil { open(&state) }
      guard let handle = state.handle else { return }
      do {
        try handle.write(contentsOf: data)
        state.size += data.count
      } catch {
        try? handle.close()
        state.handle = nil
      }
    }
  }

  private func open(_ state: inout State) {
    let fm = FileManager.default
    try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = currentFile.path
    if !fm.fileExists(atPath: path) {
      fm.createFile(atPath: path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: currentFile) else { return }
    state.size = Int((try? handle.seekToEnd()) ?? 0)
    state.handle = handle
  }

  private func rotate(_ state: inout State) {
    try? state.handle?.close()
    state.handle = nil
    state.size = 0
    let fm = FileManager.default
    try? fm.removeItem(at: file(index: maxFiles - 1))
    if maxFiles > 1 {
      for index in stride(from: maxFiles - 2, through: 0, by: -1) {
        try? fm.moveItem(at: file(index: index), to: file(index: index + 1))
      }
    }
  }
}
