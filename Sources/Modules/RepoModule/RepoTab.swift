// One repo tab (DESIGN §3.2, ADR 0013): the agent conversation, the prompt, approvals and a
// side panel with git status and the agent's todos. The agent starts lazily (first visit or
// first prompt) and resumes the repo's last session; git status follows `changes()`.
import Foundation
import Observation
import VoCoderCore
import VoCoderUI

@MainActor
@Observable
final class RepoTab: ViewTab {
  /// The agent process.
  enum Phase: Equatable {
    case notStarted
    case starting
    case running
    case failed(String)
  }

  let id: TabID
  let root: RepoRoot
  var title: String { root.name }
  var aliases: [String] { root.aliases }
  var repo: RepoRoot? { root }

  private(set) var conversation = Conversation()
  private(set) var phase = Phase.notStarted
  private(set) var status: RepoStatus?
  private(set) var gitError: String?
  var showsPanel = true
  /// The tool call picked with `[` / `]` (Enter expands it).
  private(set) var selectedTool: Int?
  private(set) var expandedTools: Set<Int> = []
  let scroll = ScrollState(followsEnd: true, pageSize: 10)
  let files = ListState(pageSize: 5)
  /// A turn finished while the tab wasn't shown (✓ until it is).
  private(set) var unseenFinish = false
  private(set) var isVisible = false

  /// The repo's path as written and resolved, for showing tool paths relative to it.
  @ObservationIgnored let rootPaths: [String]
  @ObservationIgnored let agent: (any AgentBackend)?
  @ObservationIgnored private let sourceControl: (any SourceControl)?
  @ObservationIgnored private let store: AgentSessionStore?
  @ObservationIgnored private let services: ServiceContainer
  @ObservationIgnored private let model: String?
  @ObservationIgnored private(set) var session: (any AgentSession)?
  @ObservationIgnored private var queued: [String] = []
  @ObservationIgnored private var eventsTask: Task<Void, Never>?
  @ObservationIgnored private var gitTask: Task<Void, Never>?
  @ObservationIgnored private var history: [String] = []
  @ObservationIgnored private var historyIndex: Int?
  @ObservationIgnored private var draft = ""
  @ObservationIgnored private var closing = false
  @ObservationIgnored private let log = Log(category: "repo")

  init(
    root: RepoRoot, agent: (any AgentBackend)?, sourceControl: (any SourceControl)?,
    services: ServiceContainer, model: String? = nil
  ) {
    self.root = root
    self.agent = agent
    self.sourceControl = sourceControl
    self.services = services
    self.store = services.agentSessions
    self.model = model
    id = Self.tabID(for: root)
    rootPaths = ToolSummary.roots(of: root.url)
    if sourceControl == nil { gitError = "No source control module is enabled." }
  }

  static func tabID(for root: RepoRoot) -> TabID {
    TabID("repo.\(root.url.standardizedFileURL.path)")
  }

  // MARK: Focus ids

  var conversationID: FocusID { FocusID("\(id).conversation") }
  var promptID: FocusID { FocusID("\(id).prompt") }
  var approvalID: FocusID { FocusID("\(id).approval") }
  var filesID: FocusID { FocusID("\(id).files") }
  private var host: UIHost? { services.uiHost }

  // MARK: Tab

  var badge: TabBadge {
    if conversation.pendingApproval != nil { return .needsYou }
    if phase == .starting || conversation.isWorking { return .working }
    if case .failed = phase { return .error }
    if conversation.hasError { return .error }
    return unseenFinish ? .finished : .none
  }

  var hintCommands: [CommandID] {
    if conversation.pendingApproval != nil {
      return [RepoCommands.approve, RepoCommands.approveForSession, RepoCommands.deny]
    }
    return [RepoCommands.focusPrompt, RepoCommands.interrupt, RepoCommands.togglePanel]
  }

  var closeWarning: String? {
    conversation.isWorking ? "The agent is still working; closing the tab stops it." : nil
  }

  func didActivate() {
    isVisible = true
    unseenFinish = false
    ensureStarted()
    startGit()
    focusDefault()
  }

  func didDeactivate() { isVisible = false }

  func willClose() {
    closing = true
    gitTask?.cancel()
    if let session {
      Task { await session.close() }
    }
  }

  // MARK: Agent

  /// Starts the agent unless it runs or is starting.
  func ensureStarted() {
    guard session == nil, phase != .starting, !closing else { return }
    guard let agent else {
      phase = .failed("No coding agent is enabled: enable the claude-code module in the config.")
      return
    }
    phase = .starting
    Task { await start(agent) }
  }

  private func start(_ agent: any AgentBackend) async {
    let resume = store?.lastSession(repo: root.url, backend: agent.id)
    let options = AgentSessionOptions(repo: root.url, resume: resume, model: model)
    let started: any AgentSession
    do {
      started = try await agent.startSession(options)
    } catch  where resume != nil {
      log.error("resuming \(resume?.rawValue ?? "") in \(root.name) failed: \(error)")
      store?.forget(repo: root.url, backend: agent.id)
      conversation.addNotice("Couldn't resume the last session (\(error)); starting a new one.")
      do {
        started = try await agent.startSession(
          AgentSessionOptions(repo: root.url, model: model))
      } catch {
        failStart(error)
        return
      }
    } catch {
      failStart(error)
      return
    }
    guard !closing else {
      await started.close()
      return
    }
    attach(started)
    let prompts = queued
    queued = []
    for prompt in prompts { await deliver(prompt, to: started) }
  }

  private func failStart(_ error: any Error) {
    log.error("agent start in \(root.name) failed: \(error)")
    phase = .failed("\(error)")
    conversation.addNotice(
      "\(agent?.displayName ?? "The agent") didn't start: \(error)", kind: .error)
    if !queued.isEmpty {
      queued = []
      conversation.apply(
        .turnEnd(AgentTurnEnd(outcome: .failed("not sent; send again to retry"))))
    }
  }

  private func attach(_ started: any AgentSession) {
    session = started
    phase = .running
    let events = started.events
    eventsTask = Task { [weak self] in
      for await event in events {
        guard let self else { return }
        self.handle(event)
      }
    }
  }

  func handle(_ event: AgentEvent) {
    let hadApproval = conversation.pendingApproval != nil
    conversation.apply(event)
    switch event {
    case .sessionStarted(let info):
      if let agent { store?.record(info.id, repo: root.url, backend: agent.id) }
    case .permissionRequest:
      if isVisible && !hadApproval { host?.focus.focus(approvalID) }
    case .turnEnd:
      if !isVisible { unseenFinish = true }
    case .ended:
      session = nil
      eventsTask = nil
      phase = .notStarted
    default:
      break
    }
    if hadApproval && conversation.pendingApproval == nil, isVisible,
      host?.focus.focused == approvalID
    {
      host?.focus.focus(promptID)
    }
  }

  /// Sends a prompt (starting the agent first if needed).
  func send(_ text: String) {
    let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else { return }
    if history.last != prompt { history.append(prompt) }
    historyIndex = nil
    draft = ""
    host?.setText("", for: promptID)
    conversation.addPrompt(prompt)
    selectedTool = nil
    scroll.followsEnd = true
    if let session {
      Task { await deliver(prompt, to: session) }
    } else {
      queued.append(prompt)
      ensureStarted()
    }
  }

  private func deliver(_ prompt: String, to session: any AgentSession) async {
    do {
      try await session.send(prompt)
    } catch {
      conversation.addNotice("Couldn't send the prompt: \(error)", kind: .error)
    }
  }

  /// Answers the oldest pending permission request.
  func respond(_ decision: PermissionDecision) async {
    guard let request = conversation.pendingApproval, let session else { return }
    let denied = if case .deny = decision { true } else { false }
    conversation.answered(request, denied: denied)
    if conversation.pendingApproval == nil, host?.focus.focused == approvalID {
      host?.focus.focus(promptID)
    }
    do {
      try await session.respond(to: request, decision)
    } catch {
      conversation.addNotice("Couldn't answer \(request.displayName): \(error)", kind: .error)
    }
  }

  /// Stops the running turn; while the agent is still starting, drops the queued prompts.
  func interrupt() async {
    if let session {
      await session.interrupt()
    } else if !queued.isEmpty {
      queued = []
      conversation.apply(.turnEnd(AgentTurnEnd(outcome: .interrupted)))
    }
  }

  /// Stops the agent and starts it again on the same conversation (`fresh`: a new one).
  func restart(fresh: Bool) async {
    let old = session
    session = nil
    eventsTask = nil
    await old?.close()
    if fresh, let agent { store?.forget(repo: root.url, backend: agent.id) }
    conversation.addNotice(fresh ? "Started a new conversation." : "Restarted the agent.")
    phase = .notStarted
    ensureStarted()
  }

  // MARK: Prompt

  func promptChanged(_ text: String) {
    draft = text
    historyIndex = nil
  }

  /// Up/Down in an empty (or recalled) prompt walk the history.
  func promptAction(_ action: UIAction) -> Bool {
    guard !history.isEmpty, draft.isEmpty || historyIndex != nil else { return false }
    switch action {
    case .moveUp:
      let index = max(0, (historyIndex ?? history.count) - 1)
      recall(index, cursorAtStart: true)
      return true
    case .moveDown:
      guard let current = historyIndex else { return false }
      if current + 1 < history.count {
        recall(current + 1, cursorAtStart: false)
      } else {
        historyIndex = nil
        draft = ""
        host?.setText("", for: promptID)
      }
      return true
    default:
      return false
    }
  }

  /// Shows history entry `index`. The cursor goes where the next Up (start) or Down (end)
  /// leaves the field, so walking the history doesn't stop to move through the text.
  private func recall(_ index: Int, cursorAtStart: Bool) {
    historyIndex = index
    draft = history[index]
    // setText reports no change, so the recalled index stays (promptChanged resets it).
    host?.setText(history[index], for: promptID)
    if cursorAtStart { host?.renderer.setIntegerValue(0, forWidget: promptID.rawValue) }
  }

  func focusPrompt() { host?.focus.focus(promptID) }

  /// The approval card if one waits, otherwise the prompt, unless focus is already in the tab.
  func focusDefault() {
    let ours = [conversationID, promptID, approvalID, filesID]
    if conversation.pendingApproval != nil {
      host?.focus.focus(approvalID)
    } else if let focused = host?.focus.focused, ours.contains(focused) {
      return
    } else {
      host?.focus.focus(promptID)
    }
  }

  // MARK: Tool calls

  /// Moves the tool selection by `step` (from the newest when none is selected).
  func selectTool(by step: Int) {
    let ids = conversation.toolIDs
    guard !ids.isEmpty else { return }
    let target: Int
    if let selectedTool, let index = ids.firstIndex(of: selectedTool) {
      target = min(max(index + step, 0), ids.count - 1)
    } else {
      target = step < 0 ? ids.count - 1 : 0
    }
    selectedTool = ids[target]
    scroll.followsEnd = false
  }

  func toggleSelectedTool() {
    guard let selectedTool else { return }
    if expandedTools.contains(selectedTool) {
      expandedTools.remove(selectedTool)
    } else {
      expandedTools.insert(selectedTool)
    }
  }

  /// The conversation's own handling of Enter (expand), Esc (back to following) and scrolling.
  func conversationAction(_ action: UIAction) -> Bool {
    switch action {
    case .activate:
      guard selectedTool != nil else { return false }
      toggleSelectedTool()
      return true
    case .cancel:
      guard selectedTool != nil else { return false }
      selectedTool = nil
      scroll.followsEnd = true
      return true
    case .moveUp, .moveDown, .pageUp, .pageDown, .moveToFirst, .moveToLast:
      selectedTool = nil
      return false
    default:
      return false
    }
  }

  // MARK: Git

  private func startGit() {
    guard gitTask == nil, let sourceControl else { return }
    let url = root.url
    gitTask = Task { [weak self] in
      do {
        let repository = try await sourceControl.repository(at: url)
        await self?.refreshGit(repository)
        for await _ in repository.changes() {
          guard let self else { return }
          await self.refreshGit(repository)
        }
      } catch {
        self?.gitError = "\(error)"
      }
    }
  }

  private func refreshGit(_ repository: any Repository) async {
    do {
      status = try await repository.status()
      gitError = nil
    } catch {
      gitError = "\(error)"
    }
  }
}
