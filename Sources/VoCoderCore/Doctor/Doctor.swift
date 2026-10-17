// `vocoder doctor` (DESIGN §4.9, ADR 0009): checks of the environment, the config and each
// module's setup. Core and the app contribute built-in checks; modules register their own
// through `ModuleRegistry.add(doctorCheck:)`, so a new integration brings its checks along.
import Foundation
import Synchronization

public enum DoctorStatus: Int, Sendable, Comparable, CaseIterable {
  case ok, skipped, warning, failure

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

  public var symbol: String {
    switch self {
    case .ok: "✓"
    case .skipped: "–"
    case .warning: "!"
    case .failure: "✗"
    }
  }
}

/// A check's verdict. Warnings and failures say how to fix them.
public struct DoctorResult: Sendable, Equatable {
  public var status: DoctorStatus
  public var message: String
  public var hint: String?

  public init(status: DoctorStatus, message: String, hint: String? = nil) {
    self.status = status
    self.message = message
    self.hint = hint
  }

  public static func ok(_ message: String) -> Self { Self(status: .ok, message: message) }
  public static func skipped(_ message: String) -> Self { Self(status: .skipped, message: message) }
  public static func warning(_ message: String, hint: String) -> Self {
    Self(status: .warning, message: message, hint: hint)
  }
  public static func failure(_ message: String, hint: String) -> Self {
    Self(status: .failure, message: message, hint: hint)
  }
}

/// One thing `vocoder doctor` checks. Runs off the main actor; must not prompt or change
/// anything.
public protocol DoctorCheck: Provider {
  var title: String { get }
  func run() async -> DoctorResult
}

/// A check from a closure: the app's built-in checks, and simple module checks.
public struct ClosureDoctorCheck: DoctorCheck {
  public let id: ProviderID
  public let title: String
  private let body: @Sendable () async -> DoctorResult

  public init(
    id: ProviderID, title: String, _ body: @escaping @Sendable () async -> DoctorResult
  ) {
    self.id = id
    self.title = title
    self.body = body
  }

  public func run() async -> DoctorResult { await body() }
}

public struct DoctorReport: Sendable {
  public struct Entry: Sendable {
    /// `core`, `app` or the contributing module.
    public let owner: ModuleID
    public let title: String
    public let result: DoctorResult
  }

  public var entries: [Entry]

  public var worst: DoctorStatus { entries.map(\.result.status).max() ?? .ok }

  /// One line per check, hints and extra message lines indented below.
  public func rendered(colors: Bool = false) -> String {
    let width = entries.map(\.title.count).max() ?? 0
    var lines: [String] = []
    for entry in entries {
      let status = entry.result.status
      let symbol = colors ? Self.color(status) + status.symbol + "\u{1B}[0m" : status.symbol
      let title = entry.title.padding(toLength: width, withPad: " ", startingAt: 0)
      let owner = ["core", "app"].contains(entry.owner.rawValue) ? "" : " [\(entry.owner)]"
      let messageLines = entry.result.message.split(
        separator: "\n", omittingEmptySubsequences: false)
      lines.append("\(symbol) \(title)  \(messageLines.first ?? "")\(owner)")
      for line in messageLines.dropFirst() {
        lines.append(String(repeating: " ", count: width + 4) + line)
      }
      if let hint = entry.result.hint {
        lines.append(String(repeating: " ", count: width + 4) + "→ " + hint)
      }
    }
    let counts = DoctorStatus.allCases.reversed().compactMap { status -> String? in
      let count = entries.count { $0.result.status == status }
      guard count > 0 else { return nil }
      let name =
        switch status {
        case .ok: "ok"
        case .skipped: "skipped"
        case .warning: count == 1 ? "warning" : "warnings"
        case .failure: count == 1 ? "failure" : "failures"
        }
      return "\(count) \(name)"
    }
    lines.append("")
    lines.append(counts.joined(separator: ", "))
    return lines.joined(separator: "\n")
  }

  private static func color(_ status: DoctorStatus) -> String {
    switch status {
    case .ok: "\u{1B}[32m"
    case .skipped: "\u{1B}[90m"
    case .warning: "\u{1B}[33m"
    case .failure: "\u{1B}[31m"
    }
  }
}

public enum Doctor {
  /// Runs `checks` in order. A check that takes longer than `timeout` fails (and is left to
  /// finish on its own).
  public static func run(
    _ checks: [(owner: ModuleID, check: any DoctorCheck)], timeout: Duration = .seconds(10)
  ) async -> DoctorReport {
    var entries: [DoctorReport.Entry] = []
    for (owner, check) in checks {
      let result = await run(check, timeout: timeout)
      entries.append(DoctorReport.Entry(owner: owner, title: check.title, result: result))
    }
    return DoctorReport(entries: entries)
  }

  static func run(_ check: any DoctorCheck, timeout: Duration) async -> DoctorResult {
    // Unstructured tasks: a task group would wait for a check that ignores cancellation.
    await withCheckedContinuation { continuation in
      let resumed = Mutex(false)
      let finish: @Sendable (DoctorResult) -> Void = { result in
        let first = resumed.withLock { done in
          defer { done = true }
          return !done
        }
        if first { continuation.resume(returning: result) }
      }
      Task { finish(await check.run()) }
      Task {
        try? await Task.sleep(for: timeout)
        finish(
          .failure(
            "didn't finish within \(timeout)", hint: "run `vocoder doctor` again; see `make logs`"))
      }
    }
  }
}
