import VoCoderCore

/// A request a prompter is waiting on.
public enum PromptRequest: Sendable, Equatable {
  case confirm(ConfirmRequest)
  case text(TextRequest)
  case choice(ChoiceRequest)
}

/// An answer to the newest pending request (`FakePrompter.respond`, contract suites).
public enum PromptAnswer: Sendable, Equatable {
  case confirm(Bool)
  case text(String)
  case choice(String)
  case cancel
}

/// Records requests and notices. Requests wait until `respond` answers the newest (or
/// `cancelAll`), unless `autoAnswer` answers them on arrival.
@MainActor
public final class FakePrompter: CommandPrompter {
  /// Every request, in arrival order.
  public private(set) var requests: [PromptRequest] = []
  public private(set) var notices: [Notice] = []
  /// Answers a request on arrival; nil leaves it pending.
  public var autoAnswer: (@MainActor (PromptRequest) -> PromptAnswer?)?

  private var pending: [(request: PromptRequest, resume: (PromptAnswer) -> Void)] = []

  public init(autoAnswer: (@MainActor (PromptRequest) -> PromptAnswer?)? = nil) {
    self.autoAnswer = autoAnswer
  }

  public var pendingRequests: [PromptRequest] { pending.map(\.request) }

  public func confirm(_ request: ConfirmRequest) async -> Bool {
    if case .confirm(let yes) = await ask(.confirm(request)) { return yes }
    return false
  }

  public func askText(_ request: TextRequest) async -> String? {
    if case .text(let text) = await ask(.text(request)) { return text }
    return nil
  }

  public func choose(_ request: ChoiceRequest) async -> String? {
    if case .choice(let value) = await ask(.choice(request)) { return value }
    return nil
  }

  public func notify(_ notice: Notice) { notices.append(notice) }

  public func cancelAll() {
    while !pending.isEmpty { respond(.cancel) }
  }

  /// Answers the newest pending request. Returns false if none is pending.
  @discardableResult
  public func respond(_ answer: PromptAnswer) -> Bool {
    guard let last = pending.popLast() else { return false }
    last.resume(answer)
    return true
  }

  private func ask(_ request: PromptRequest) async -> PromptAnswer {
    requests.append(request)
    if let answer = autoAnswer?(request) { return answer }
    return await withCheckedContinuation { continuation in
      pending.append((request, { continuation.resume(returning: $0) }))
    }
  }
}
