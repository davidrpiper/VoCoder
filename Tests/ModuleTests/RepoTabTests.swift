import Foundation
import Testing
import VoCoderCore
import VoCoderFakes
import VoCoderTestSupport
import VoCoderUI
import VoCoderUITestSupport

@testable import RepoModule

// MARK: - Conversation (pure)

@Suite struct ConversationTests {
  @Test func deltasStreamIntoOneMessageThatTheTextReplaces() {
    var conversation = Conversation()
    conversation.apply(.textDelta(AgentTextDelta(messageID: "m1", text: "Hel")))
    conversation.apply(.textDelta(AgentTextDelta(messageID: "m1", text: "lo **wor")))
    guard case .message(let streaming) = conversation.entries.last else {
      Issue.record("no message")
      return
    }
    #expect(streaming.isStreaming)
    #expect(streaming.text == "Hello **wor")
    #expect(streaming.document == MarkdownDocument(parsing: "Hello **wor"))
    conversation.apply(.text(AgentText(messageID: "m1", text: "Hello **world**")))
    #expect(conversation.entries.count == 1)
    guard case .message(let done) = conversation.entries.last else { return }
    #expect(!done.isStreaming)
    #expect(done.document == MarkdownDocument(parsing: "Hello **world**"))
  }

  @Test func blocksOfOneMessageAreSeparateEntries() {
    var conversation = Conversation()
    conversation.apply(.textDelta(AgentTextDelta(messageID: "m1", text: "a")))
    conversation.apply(.text(AgentText(messageID: "m1", text: "a")))
    conversation.apply(.textDelta(AgentTextDelta(messageID: "m1", text: "b")))
    conversation.apply(.text(AgentText(messageID: "m1", text: "b")))
    conversation.apply(.text(AgentText(messageID: "m2", text: "c")))  // no deltas
    conversation.apply(.text(AgentText(messageID: "m3", text: "")))  // nothing to show
    let texts = conversation.entries.compactMap { entry -> String? in
      if case .message(let message) = entry { message.text } else { nil }
    }
    #expect(texts == ["a", "b", "c"])
  }

  @Test func toolCallsCollectResultsAndApprovals() {
    var conversation = Conversation()
    let use = AgentToolUse(id: "t1", name: "Bash", input: .object(["command": "git status"]))
    conversation.apply(.toolUse(use))
    let request = PermissionRequest(
      id: "p1", toolName: "Bash", input: use.input, toolUseID: "t1")
    conversation.apply(.permissionRequest(request))
    #expect(conversation.pendingApproval == request)
    guard case .tool(let waiting) = conversation.entries.last else { return }
    #expect(waiting.awaitingApproval)
    #expect(ToolSummary.summary(name: "Bash", input: waiting.use.input) == "git status")

    conversation.answered(request, denied: true)
    #expect(conversation.pendingApproval == nil)
    conversation.apply(
      .toolResult(AgentToolResult(toolUseID: "t1", toolName: "Bash", content: "no", isError: true)))
    guard case .tool(let done) = conversation.entries.last else { return }
    #expect(done.denied)
    #expect(!done.awaitingApproval)
    #expect(done.result?.isError == true)
    #expect(conversation.toolIDs == [done.id])
  }

  @Test func turnEndDropsStaleApprovalsAndAddsAFooter() {
    var conversation = Conversation()
    conversation.addPrompt("go")
    #expect(conversation.isWorking)
    conversation.apply(.textDelta(AgentTextDelta(messageID: "m1", text: "part")))
    conversation.apply(
      .permissionRequest(PermissionRequest(id: "p1", toolName: "Bash", input: .null)))
    conversation.apply(.turnEnd(AgentTurnEnd(outcome: .failed("overloaded"))))
    #expect(conversation.approvals.isEmpty)
    #expect(!conversation.isWorking)
    #expect(conversation.hasError)
    guard case .message(let message) = conversation.entries[1] else { return }
    #expect(!message.isStreaming)
    guard case .turnEnd(_, let end) = conversation.entries.last else { return }
    #expect(end.outcome == .failed("overloaded"))
    conversation.addPrompt("again")
    #expect(!conversation.hasError)
  }

  @Test func errorsBackgroundTasksAndTheEndBecomeNotices() {
    var conversation = Conversation()
    conversation.apply(.error(.crashed(status: 1, restarting: 1)))
    conversation.apply(
      .backgroundTask(AgentBackgroundTask(id: "b", description: "tests", status: .running)))
    conversation.apply(
      .backgroundTask(AgentBackgroundTask(id: "b", description: "tests", status: .failed)))
    conversation.apply(.spokenSummary("All done."))
    conversation.apply(.ended(.exited(status: 9)))
    let notices = conversation.entries.compactMap { entry -> Conversation.Notice? in
      if case .notice(_, let notice) = entry { notice } else { nil }
    }
    #expect(
      notices.map(\.text) == [
        "The agent exited (status 1); restarting (attempt 1)",
        "Background task failed: tests",
        "The agent stopped (exit status 9). Send a prompt to restart it.",
      ])
    #expect(notices.allSatisfy { $0.kind == .error })
    #expect(conversation.ended == .exited(status: 9))
    #expect(conversation.lastSpoken == "All done.")
  }

  @Test func subAgentTextIsNested() {
    var conversation = Conversation()
    conversation.apply(.text(AgentText(messageID: "m", text: "inner", parentToolUseID: "t")))
    guard case .message(let message) = conversation.entries.last else { return }
    #expect(message.isNested)
  }
}

@Suite struct ToolSummaryTests {
  @Test func summaryPrefersTellingKeys() {
    #expect(
      ToolSummary.summary(
        name: "Bash", input: .object(["description": "List", "command": "ls -la"])) == "ls -la")
    #expect(
      ToolSummary.summary(name: "Read", input: .object(["file_path": "/a/b.swift"]))
        == "/a/b.swift")
    #expect(ToolSummary.summary(name: "X", input: .object(["zeta": "z", "alpha": "a"])) == "a")
    #expect(ToolSummary.summary(name: "X", input: .object(["n": 3])) == "")
    #expect(ToolSummary.summary(name: "X", input: .null) == "")
  }

  @Test func pathsInTheRepoAreRelative() {
    let input = JSONValue.object(["file_path": "/private/var/repo/Sources/a.swift"])
    #expect(
      ToolSummary.summary(name: "Read", input: input, roots: ["/var/repo", "/private/var/repo"])
        == "Sources/a.swift")
    #expect(ToolSummary.summary(name: "Read", input: input, roots: ["/elsewhere"]).hasPrefix("/"))
    let temp = FileManager.default.temporaryDirectory
    #expect(ToolSummary.roots(of: temp).count == 2)  // /var/folders/… is /private/var/…
  }

  @Test func oneLineCutsAtTheFirstLineOrTheLimit() {
    #expect(ToolSummary.oneLine("  one\ntwo ") == "one …")
    #expect(ToolSummary.oneLine("abcdef", limit: 3) == "abc …")
    #expect(ToolSummary.oneLine("abc") == "abc")
  }

  @Test func truncationCountsOmittedLines() {
    let (lines, omitted) = ToolSummary.truncated("1\n2\n3\n4\n", maxLines: 2)
    #expect(lines == ["1", "2"])
    #expect(omitted == 2)
    #expect(ToolSummary.truncated("a\n", maxLines: 5).lines == ["a"])
    #expect(ToolSummary.truncated("", maxLines: 5).lines == [])
  }

  @Test func detailShowsTheWholeCommandOrJSON() {
    #expect(ToolSummary.detail(of: .object(["command": "a\nb"])) == "a\nb")
    #expect(ToolSummary.detail(of: .object(["n": 1])) == JSONValue.object(["n": 1]).jsonString)
  }

  @Test func turnFooter() {
    #expect(
      TurnFooter.text(
        AgentTurnEnd(outcome: .completed, duration: .milliseconds(12_340), costUSD: 0.041))
        == "── done · 12.3 s · $0.04 ──")
    #expect(TurnFooter.text(AgentTurnEnd(outcome: .interrupted)) == "── interrupted ──")
  }
}

// MARK: - The tab in the chrome

/// Fake providers for the repo tab, configured per test (the suite is serialized).
final class RepoTestProviders: VoCoderModule {
  static let id: ModuleID = "repo-test"
  @MainActor static var agent: any AgentBackend = FakeAgentBackend()
  @MainActor static var sourceControl = FakeSourceControl()

  init(context: ModuleContext) {}

  func register(into registry: inout ModuleRegistry) {
    registry.add(agent: Self.agent)
    registry.add(sourceControl: Self.sourceControl)
  }
}

/// Rejects resuming (an unknown session id), like Claude Code's startup failure.
final class ResumeRejectingBackend: AgentBackend {
  let id: ProviderID = "rejecting"
  let displayName = "Rejecting"
  let inner = FakeAgentBackend()

  func startSession(_ options: AgentSessionOptions) async throws -> any AgentSession {
    if options.resume != nil { throw AgentError.launchFailed("no such session") }
    return try await inner.startSession(options)
  }
}

/// Behaviors for the tests' fake agent.
enum Scripts {
  /// Asks to run `rm -rf build`, then reports the decision.
  static let askFirst: FakeAgentBackend.Behavior = { session, _ in
    session.beginTurn()
    let use = AgentToolUse(
      id: "t-\(session.nextMessageID())", name: "Bash",
      input: .object(["command": "rm -rf build", "description": "Clean the build"]))
    session.emit(.toolUse(use))
    let decision = await session.requestPermission(
      PermissionRequest(
        id: "p-\(use.id)", toolName: "Bash", input: use.input, description: "Clean the build",
        toolUseID: use.id, offersSessionRule: true))
    let denied = if case .deny = decision { true } else { false }
    session.emit(
      .toolResult(
        AgentToolResult(
          toolUseID: use.id, toolName: "Bash", content: denied ? "denied" : "removed",
          isError: denied)))
    session.endTurn(.completed)
  }

  /// Starts a turn and never ends it (until interrupted).
  static let hang: FakeAgentBackend.Behavior = { session, _ in
    session.beginTurn()
    session.emit(.textDelta(AgentTextDelta(messageID: session.nextMessageID(), text: "Thinking")))
    try? await Task.sleep(for: .seconds(3600))
  }

  /// A long tool result, a sub-agent and todos, for the expanded snapshot.
  static let rich: FakeAgentBackend.Behavior = { session, _ in
    session.beginTurn()
    let use = AgentToolUse(
      id: "t1", name: "Bash", input: .object(["command": "swift test 2>&1 | tail -n 20"]))
    session.emit(.toolUse(use))
    let output = (1...20).map { "line \($0)" }.joined(separator: "\n")
    session.emit(.toolResult(AgentToolResult(toolUseID: "t1", toolName: "Bash", content: output)))
    let task = AgentToolUse(
      id: "t2", name: "Task", input: .object(["description": "Search for callers"]))
    session.emit(.toolUse(task))
    session.emit(
      .text(AgentText(messageID: "sub", text: "Found **3** callers.", parentToolUseID: "t2")))
    session.emit(
      .toolUse(
        AgentToolUse(
          id: "t3", name: "Grep", input: .object(["pattern": "send("]), parentToolUseID: "t2")))
    session.emit(.toolResult(AgentToolResult(toolUseID: "t3", toolName: "Grep", content: "a\nb")))
    session.emit(.toolResult(AgentToolResult(toolUseID: "t2", toolName: "Task", content: "ok")))
    session.emit(
      .todos([
        AgentTodo(id: "1", subject: "Run the tests", status: .completed),
        AgentTodo(id: "2", subject: "Fix the flaky one", status: .inProgress),
        AgentTodo(id: "3", subject: "Write it up"),
      ]))
    session.emit(.text(AgentText(messageID: session.nextMessageID(), text: "All **20** pass.")))
    session.endTurn(.completed)
  }
}

@MainActor
@Suite(.serialized) final class RepoTabTests {
  let host = UIHost(theme: .dark)
  let directory: URL
  let store: AgentSessionStore
  let root = RepoRoot(url: URL(filePath: "/work/api-server"), aliases: ["the api"])
  var shell: AppShell!
  var core: AppCore { shell.core }

  init() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "repo-tab-\(UUID().uuidString)")
    store = AgentSessionStore(file: directory.appending(path: "sessions.json"))
    RepoTestProviders.agent = FakeAgentBackend()
    RepoTestProviders.sourceControl = FakeSourceControl()
    RepoTestProviders.sourceControl.makeRepository(
      at: root.url, files: ["README.md": "hi\n", "main.swift": "print(1)\n"])
  }

  deinit { try? FileManager.default.removeItem(at: directory) }

  /// Loads the modules and opens the tabs (call after configuring `RepoTestProviders`).
  func start() {
    var environment = ModuleEnvironment(secrets: InMemorySecretStore(), repos: [root])
    environment.services.agentSessions = store
    shell = AppShell(
      modules: [RepoTestProviders.self, RepoModule.self], environment: environment, host: host,
      quit: {})
    shell.toasts.sleep = { _ in try await Task.sleep(for: .seconds(3600)) }
    shell.start()
  }

  var tab: RepoTab { core.state.tabs[1] as! RepoTab }
  var fake: FakeAgentBackend { RepoTestProviders.agent as! FakeAgentBackend }

  func type(_ input: String) {
    host.renderer.onEvent = { [host] event in MainActor.assumeIsolated { host.handle(event) } }
    host.renderer.injectInput(input)
    host.renderIfNeeded()
  }

  /// Selects the repo tab and renders, so the prompt has focus.
  func openTab() {
    core.state.select(tab.id)
    host.render()
  }

  // MARK: Lifecycle

  @Test func agentStartsOnFirstVisitAndRemembersTheSession() async {
    start()
    #expect(core.state.tabs.map(\.title) == ["Home", "api-server"])
    #expect(tab.repo == root)
    #expect(fake.sessions.isEmpty)
    openTab()
    #expect(await eventually { self.tab.phase == .running })
    #expect(fake.sessions.first?.options.repo == root.url)
    #expect(fake.sessions.first?.options.resume == nil)
    type("hello\r")
    #expect(await eventually { self.fake.sessions.first?.prompts == ["hello"] })
    #expect(
      await eventually { self.tab.badge == TabBadge.none && !self.tab.conversation.isWorking })
    #expect(store.lastSession(repo: root.url, backend: fake.id) == "fake-session-1")
    core.stop()
  }

  @Test func resumesTheStoredSession() async {
    store.record("earlier", repo: root.url, backend: "fake-agent")
    start()
    openTab()
    #expect(await eventually { self.fake.sessions.count == 1 })
    #expect(fake.sessions[0].options.resume == "earlier")
    core.stop()
  }

  @Test func anUnknownResumeIDStartsANewSession() async {
    let backend = ResumeRejectingBackend()
    RepoTestProviders.agent = backend
    store.record("gone", repo: root.url, backend: backend.id)
    start()
    openTab()
    #expect(await eventually { self.tab.phase == .running })
    #expect(backend.inner.sessions.count == 1)
    #expect(store.lastSession(repo: root.url, backend: backend.id) == nil)
    let notices = tab.conversation.entries.compactMap { entry -> String? in
      if case .notice(_, let notice) = entry { notice.text } else { nil }
    }
    #expect(notices.first?.hasPrefix("Couldn't resume the last session") == true)
    core.stop()
  }

  @Test func aFailedStartShowsTheErrorAndDropsQueuedPrompts() async {
    RepoTestProviders.agent = FakeAgentBackend(failure: .executableNotFound("claude"))
    start()
    openTab()
    #expect(await eventually { self.tab.badge == .error })
    type("anyone?\r")
    #expect(await eventually { self.tab.conversation.entries.count >= 4 })
    assertSnapshot(of: host, width: 80, height: 24)
    core.stop()
  }

  @Test func promptsSentBeforeTheAgentRunsAreDelivered() async {
    start()
    tab.send("early")  // not visited yet: starts the agent
    #expect(await eventually { self.fake.sessions.first?.prompts == ["early"] })
    core.stop()
  }

  @Test func closingTheTabClosesTheSessionAndAsksWhileWorking() async {
    RepoTestProviders.agent = FakeAgentBackend(behavior: Scripts.hang)
    start()
    openTab()
    type("work\r")
    #expect(await eventually { self.tab.badge == .working })
    #expect(tab.closeWarning != nil)
    type("\0tc")  // tab.close: confirm first
    #expect(await eventually { self.shell.modals.top != nil })
    type("\u{1B}")  // cancel
    #expect(await eventually { self.shell.modals.top == nil })
    #expect(core.state.tabs.count == 2)
    type("\0tc")
    #expect(await eventually { self.shell.modals.top != nil })
    type("y")
    #expect(await eventually { self.core.state.tabs.count == 1 })
    #expect(await eventually { self.fake.sessions.first?.isClosed == true })
    core.stop()
  }

  @Test func anEndedAgentRestartsOnTheNextPrompt() async {
    start()
    openTab()
    type("one\r")
    #expect(await eventually { self.fake.sessions.first?.prompts == ["one"] })
    #expect(await eventually { !self.tab.conversation.isWorking })
    tab.handle(.error(.crashed(status: 1, restarting: nil)))
    tab.handle(.ended(.exited(status: 1)))
    #expect(tab.phase == .notStarted)
    #expect(tab.badge == .error)
    type("two\r")
    #expect(await eventually { self.fake.sessions.count == 2 })
    #expect(fake.sessions[1].options.resume == "fake-session-1")
    #expect(await eventually { self.fake.sessions[1].prompts == ["two"] })
    core.stop()
  }

  // MARK: Approvals

  @Test func approvalCardAnswersFromKeys() async {
    RepoTestProviders.agent = FakeAgentBackend(behavior: Scripts.askFirst)
    start()
    openTab()
    type("clean\r")
    #expect(await eventually { self.tab.badge == .needsYou })
    host.render()
    #expect(host.focus.path.contains(tab.approvalID))
    #expect(tab.hintCommands.first == RepoCommands.approve)
    assertSnapshot(of: host, width: 80, height: 24, named: "card")
    type("s")  // allow for the session: no second confirm from keys
    #expect(shell.modals.top == nil)
    #expect(await eventually { self.fake.sessions.first?.decisions.count == 1 })
    #expect(fake.sessions[0].decisions[0].decision == .allowForSession)
    #expect(await eventually { !self.tab.conversation.isWorking })
    host.render()
    #expect(host.focus.focused == tab.promptID)

    type("again\r")
    #expect(await eventually { self.tab.badge == .needsYou })
    type("d")
    #expect(await eventually { self.fake.sessions.first?.decisions.count == 2 })
    #expect(fake.sessions[0].decisions[1].decision == .deny(message: RepoCommands.denyMessage))
    #expect(await eventually { !self.tab.conversation.isWorking })
    assertSnapshot(of: host, width: 80, height: 24, named: "denied")
    core.stop()
  }

  @Test func denyWithAReasonTellsTheAgent() async {
    RepoTestProviders.agent = FakeAgentBackend(behavior: Scripts.askFirst)
    start()
    openTab()
    type("clean\r")
    #expect(await eventually { self.tab.badge == .needsYou })
    host.render()
    type("D")
    #expect(await eventually { self.shell.modals.top != nil })
    type("keep the cache\r")
    #expect(await eventually { self.fake.sessions.first?.decisions.count == 1 })
    #expect(fake.sessions[0].decisions[0].decision == .deny(message: "keep the cache"))
    core.stop()
  }

  @Test func voiceApprovalStillConfirms() async throws {
    RepoTestProviders.agent = FakeAgentBackend(behavior: Scripts.askFirst)
    start()
    openTab()
    type("clean\r")
    #expect(await eventually { self.tab.badge == .needsYou })
    let run = Task { try await self.core.run(RepoCommands.approve, source: .voice) }
    #expect(await eventually { self.shell.modals.top != nil })
    shell.modals.answerConfirm(true)
    _ = try await run.value
    #expect(await eventually { self.fake.sessions.first?.decisions.count == 1 })
    core.stop()
  }

  // MARK: Conversation and prompt

  @Test func interruptStopsTheTurn() async {
    RepoTestProviders.agent = FakeAgentBackend(behavior: Scripts.hang)
    start()
    openTab()
    type("go\r")
    #expect(await eventually { self.tab.badge == .working })
    #expect(await eventually { self.fake.sessions.first?.prompts == ["go"] })
    type("\0x")
    #expect(await eventually { self.fake.sessions.first?.interrupts == 1 })
    #expect(await eventually { self.tab.badge == TabBadge.none })
    guard case .turnEnd(_, let end) = tab.conversation.entries.last else {
      Issue.record("no turn end")
      return
    }
    #expect(end.outcome == .interrupted)
    core.stop()
  }

  @Test func promptHistoryAndNewlines() async {
    start()
    openTab()
    type("first\r")
    type("two\u{1B}\rlines\r")  // Alt-Enter: a newline in the prompt
    #expect(await eventually { self.fake.sessions.first?.prompts == ["first", "two\nlines"] })
    #expect(host.text(of: tab.promptID) == "")
    type("\u{1B}[A")  // Up
    #expect(host.text(of: tab.promptID) == "two\nlines")
    type("\u{1B}[A")
    #expect(host.text(of: tab.promptID) == "first")
    type("\u{1B}[A")  // the oldest stays
    #expect(host.text(of: tab.promptID) == "first")
    type("\u{1B}[B")  // Down
    #expect(host.text(of: tab.promptID) == "two\nlines")
    type("\u{1B}[B")
    #expect(host.text(of: tab.promptID) == "")
    core.stop()
  }

  @Test func toolCallsExpandAndThePanelToggles() async {
    RepoTestProviders.agent = FakeAgentBackend(behavior: Scripts.rich)
    start()
    openTab()
    type("test it\r")
    #expect(await eventually { !self.tab.conversation.isWorking && self.tab.status != nil })
    host.focus.focus(tab.conversationID)
    host.render()
    type("[")  // the newest tool call (Grep, nested)
    type("[")
    type("[")  // the first (Bash)
    type("\r")
    #expect(tab.expandedTools.count == 1)
    assertSnapshot(of: host, width: 120, height: 40, named: "expanded")
    type("\u{1B}")
    #expect(tab.selectedTool == nil)
    #expect(tab.scroll.followsEnd)
    type("\0rp")
    #expect(!tab.showsPanel)
    assertSnapshot(of: host, width: 80, height: 24, named: "no-panel")
    core.stop()
  }

  @Test func gitPanelFollowsChanges() async throws {
    start()
    openTab()
    #expect(await eventually { self.tab.status?.isClean == true })
    let repository = try await RepoTestProviders.sourceControl.repository(at: root.url)
    (repository as! FakeRepository).write("new.txt", "x")
    #expect(await eventually { self.tab.status?.files.map(\.path) == ["new.txt"] })
    core.stop()
  }

  @Test func aTurnFinishedOutOfSightShowsATick() async {
    start()
    openTab()
    #expect(await eventually { self.tab.phase == .running })
    core.state.select("home")
    tab.handle(.turnEnd(AgentTurnEnd(outcome: .completed)))
    #expect(tab.badge == .finished)
    openTab()
    #expect(tab.badge == TabBadge.none)
    core.stop()
  }

  @Test func withoutAnAgentTheTabSaysSo() {
    var environment = ModuleEnvironment(secrets: InMemorySecretStore(), repos: [root])
    environment.services.agentSessions = store
    shell = AppShell(modules: [RepoModule.self], environment: environment, host: host, quit: {})
    shell.start()
    openTab()
    #expect(tab.badge == .error)
    assertSnapshot(of: host, width: 80, height: 24)
    core.stop()
  }
}
