// Questions a running command asks the user (ADR 0008): confirm, enter text, pick from a list,
// plus fire-and-forget notices. The chrome answers them with modals and toasts (P1-07); voice
// answers them by speech (P2-07). Core only sees this protocol.

/// Asks the user while a command runs. Every request resolves exactly once: answered, cancelled
/// by the user, or cancelled by `cancelAll()` (the app stopping). Cancelled confirms are `false`,
/// cancelled text and choices `nil`. Requests made while another is pending stack: the newest is
/// answered first.
@MainActor
public protocol CommandPrompter: AnyObject {
  func confirm(_ request: ConfirmRequest) async -> Bool
  func askText(_ request: TextRequest) async -> String?
  /// The chosen `Choice.value`.
  func choose(_ request: ChoiceRequest) async -> String?
  /// Shows a short message without waiting (a toast).
  func notify(_ notice: Notice)
  /// Resolves every pending request as cancelled.
  func cancelAll()
}

public struct ConfirmRequest: Sendable, Equatable {
  public var title: String
  public var message: String
  public var confirmTitle: String
  public var cancelTitle: String
  /// Whether "confirm" starts focused. Outward commands start on "cancel" (ADR 0008), so a
  /// reflexive Enter doesn't send anything.
  public var confirmIsDefault: Bool

  public init(
    title: String, message: String = "", confirmTitle: String = "Confirm",
    cancelTitle: String = "Cancel", confirmIsDefault: Bool = false
  ) {
    self.title = title
    self.message = message
    self.confirmTitle = confirmTitle
    self.cancelTitle = cancelTitle
    self.confirmIsDefault = confirmIsDefault
  }
}

public struct TextRequest: Sendable, Equatable {
  public var title: String
  public var placeholder: String
  /// The text the field starts with.
  public var initial: String

  public init(title: String, placeholder: String = "", initial: String = "") {
    self.title = title
    self.placeholder = placeholder
    self.initial = initial
  }
}

public struct ChoiceRequest: Sendable, Equatable {
  public var title: String
  public var choices: [CommandParameter.Choice]

  public init(title: String, choices: [CommandParameter.Choice]) {
    self.title = title
    self.choices = choices
  }
}

public struct Notice: Sendable, Equatable {
  public enum Kind: Sendable, Equatable { case info, success, error }

  public var message: String
  public var kind: Kind

  public init(_ message: String, kind: Kind = .info) {
    self.message = message
    self.kind = kind
  }
}

/// Used when no prompter is attached (headless runs, early startup): declines every question
/// and logs notices.
@MainActor
public final class DecliningPrompter: CommandPrompter {
  public static let shared = DecliningPrompter()
  private let log = Log(category: "prompts")

  public init() {}

  public func confirm(_ request: ConfirmRequest) async -> Bool {
    log.info("declined confirm '\(request.title)': no prompter")
    return false
  }

  public func askText(_ request: TextRequest) async -> String? { nil }
  public func choose(_ request: ChoiceRequest) async -> String? { nil }
  public func notify(_ notice: Notice) { log.info("notice: \(notice.message)") }
  public func cancelAll() {}
}
