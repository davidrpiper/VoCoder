// The chrome's modal system (ADR 0008): answers `CommandPrompter` requests with a confirm
// dialog, a text prompt or a filterable list picker, and confirms outward commands
// (`CommandConfirmer`). Modals stack; the top one has focus (a trap scope) and is answered first.
// Keys reach them through the navigation commands (Enter, Esc, arrows, Tab) and `modal.confirm` /
// `modal.deny` (y / n on a confirm dialog).
import Observation
import VoCoderCore

@MainActor
@Observable
public final class ModalPresenter: CommandPrompter, CommandConfirmer {
  public enum Kind {
    case confirm(ConfirmRequest)
    case text(TextRequest)
    case choice(ChoiceRequest)
  }

  @MainActor
  @Observable
  public final class Modal: Identifiable {
    public let id: Int
    public let kind: Kind
    /// Choice pickers: the filter text and the selected row.
    public internal(set) var query = ""
    public let list = ListState(pageSize: 8)
    @ObservationIgnored fileprivate let resume: (Answer) -> Void

    fileprivate init(id: Int, kind: Kind, resume: @escaping (Answer) -> Void) {
      self.id = id
      self.kind = kind
      self.resume = resume
    }

    /// The focus scope (a trap) and its parts.
    public var scopeID: FocusID { FocusID("modal.\(id)") }
    public var confirmButtonID: FocusID { FocusID("modal.\(id).confirm") }
    public var cancelButtonID: FocusID { FocusID("modal.\(id).cancel") }
    public var fieldID: FocusID { FocusID("modal.\(id).field") }

    /// Choices matching the filter, best first (all of them, in order, for an empty filter).
    public var filteredChoices: [CommandParameter.Choice] {
      guard case .choice(let request) = kind else { return [] }
      let scored = request.choices.enumerated().compactMap { offset, choice in
        FuzzyMatcher.score(query, in: choice.title).map { (choice, $0, offset) }
      }
      return scored.sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }.map(\.0)
    }
  }

  fileprivate enum Answer {
    case confirm(Bool)
    case text(String?)
  }

  /// Bottom to top.
  public private(set) var stack: [Modal] = []
  @ObservationIgnored private weak var host: UIHost?
  @ObservationIgnored private let toasts: ToastCenter?
  @ObservationIgnored private var nextID = 1
  @ObservationIgnored private let log = Log(category: "modals")

  /// `host` gets focus requests and field text; notices go to `toasts`.
  public init(host: UIHost?, toasts: ToastCenter? = nil) {
    self.host = host
    self.toasts = toasts
  }

  public var top: Modal? { stack.last }

  // MARK: CommandPrompter

  public func confirm(_ request: ConfirmRequest) async -> Bool {
    if case .confirm(let yes) = await present(.confirm(request)) { return yes }
    return false
  }

  public func askText(_ request: TextRequest) async -> String? {
    if case .text(let text) = await present(.text(request)) { return text }
    return nil
  }

  public func choose(_ request: ChoiceRequest) async -> String? {
    if case .text(let value) = await present(.choice(request)) { return value }
    return nil
  }

  public func notify(_ notice: Notice) {
    if let toasts { toasts.show(notice) } else { log.info("notice: \(notice.message)") }
  }

  public func cancelAll() {
    while !stack.isEmpty { cancelTop() }
  }

  // MARK: CommandConfirmer

  /// "Post a comment?" with the arguments, starting on Cancel (ADR 0008).
  public func confirm(_ command: Command, in context: CommandContext) async -> Bool {
    let arguments = command.params.compactMap { parameter -> String? in
      guard let value = context.arguments[parameter.name] else { return nil }
      let text = value.text
      let shown = text.count > 60 ? String(text.prefix(59)) + "…" : text
      return "\(parameter.title): \(shown)"
    }
    let message = (arguments + ["This acts outside VoCoder."]).joined(separator: "\n")
    return await confirm(
      ConfirmRequest(title: "\(command.title)?", message: message, confirmTitle: command.title))
  }

  // MARK: Answering (views and commands)

  /// Answers the top confirm dialog.
  public func answerConfirm(_ yes: Bool) {
    guard let top, case .confirm = top.kind else { return }
    finish(top, .confirm(yes))
  }

  /// Submits the top text prompt or list picker (the selected choice).
  public func submit(_ text: String) {
    guard let top else { return }
    switch top.kind {
    case .confirm: return
    case .text: finish(top, .text(text))
    case .choice:
      let choices = top.filteredChoices
      guard let index = top.list.selectedIndex(count: choices.count) else { return }
      finish(top, .text(choices[index].value))
    }
  }

  /// Cancels the top modal.
  public func cancelTop() {
    guard let top else { return }
    switch top.kind {
    case .confirm: finish(top, .confirm(false))
    case .text, .choice: finish(top, .text(nil))
    }
  }

  func queryChanged(_ text: String) {
    guard let top else { return }
    top.query = text
    top.list.selection = 0
  }

  /// Esc cancels; arrows move between buttons or through the choices.
  func handle(_ action: UIAction, in modal: Modal) -> Bool {
    switch (action, modal.kind) {
    case (.cancel, _):
      cancelTop()
      return true
    case (.moveLeft, .confirm):
      host?.focus.focus(modal.cancelButtonID)
      return true
    case (.moveRight, .confirm):
      host?.focus.focus(modal.confirmButtonID)
      return true
    case (.moveUp, .choice), (.moveDown, .choice), (.pageUp, .choice), (.pageDown, .choice):
      let handled = modal.list.perform(action, count: modal.filteredChoices.count)
      host?.invalidate()
      return handled
    default:
      return false
    }
  }

  // MARK: Presenting

  private func present(_ kind: Kind) async -> Answer {
    await withCheckedContinuation { continuation in
      let modal = Modal(id: nextID, kind: kind) { continuation.resume(returning: $0) }
      nextID += 1
      stack.append(modal)
      log.debug("modal \(modal.id) shown")
      switch kind {
      case .confirm(let request):
        host?.focus.focus(request.confirmIsDefault ? modal.confirmButtonID : modal.cancelButtonID)
      case .text(let request):
        host?.setText(request.initial, for: modal.fieldID)
        host?.focus.focus(modal.fieldID)
      case .choice:
        host?.setText("", for: modal.fieldID)
        host?.focus.focus(modal.fieldID)
      }
    }
  }

  private func finish(_ modal: Modal, _ answer: Answer) {
    stack.removeAll { $0 === modal }
    log.debug("modal \(modal.id) answered")
    modal.resume(answer)
  }
}

/// `modal.confirm` / `modal.deny`: y and n on a confirm dialog (Enter and Esc work through the
/// navigation commands).
public enum ModalCommands {
  public static let confirm: CommandID = "modal.confirm"
  public static let deny: CommandID = "modal.deny"

  static func make(for presenter: ModalPresenter) -> [Command] {
    let onConfirmDialog: Command.Availability = { [weak presenter] context in
      guard let top = presenter?.top, case .confirm = top.kind else { return false }
      return context.focus.contains(top.scopeID.rawValue)
    }
    return [
      Command(
        id: confirm, title: "Confirm", category: "Dialog", keys: ["y"],
        voicePhrases: ["confirm", "yes"], isAvailable: onConfirmDialog
      ) { [weak presenter] _ in
        presenter?.answerConfirm(true)
      },
      Command(
        id: deny, title: "Cancel", category: "Dialog", keys: ["n"], voicePhrases: ["no"],
        isAvailable: onConfirmDialog
      ) { [weak presenter] _ in
        presenter?.answerConfirm(false)
      },
    ]
  }
}
