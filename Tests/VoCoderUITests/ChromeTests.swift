import Foundation
import Observation
import Testing
import VoCoderCore
import VoCoderFakes
import VoCoderTestSupport
import VoCoderUITestSupport

@testable import VoCoderUI

/// A repo-style tab per configured repo root, with a badge and hint commands.
@MainActor
@Observable
final class ChromeRepoTab: ViewTab {
  let id: TabID
  var title: String
  let aliases: [String]
  var badge: TabBadge
  let hintCommands: [CommandID] = ["test.publish", "test.rename"]

  init(id: TabID, title: String, aliases: [String] = [], badge: TabBadge = .none) {
    self.id = id
    self.title = title
    self.aliases = aliases
    self.badge = badge
  }

  var body: some View {
    VStack {
      Text("Repository \(title)").bold()
      Paragraph("Conversation and side panel arrive with the repo tab (P1-10).")
    }
  }
}

/// What the test commands saw.
@MainActor
final class ChromeLog {
  var published = 0
  var names: [String?] = []
  var picks: [String?] = []
}

/// One tab per repo root (badges cycle through every kind), and commands that use each modal.
final class ChromeTestModule: VoCoderModule {
  static let id: ModuleID = "chrome-test"
  @MainActor static let log = ChromeLog()

  init(context: ModuleContext) {}

  func register(into registry: inout ModuleRegistry) {
    let badges: [TabBadge] = [.working, .needsYou, .finished, .error, .count(3), .text("10:30")]
    registry.add(
      tabs: TabFactory(id: "chrome.repos", placement: .repo) { context in
        context.repos.enumerated().map { index, repo in
          let name = repo.url.lastPathComponent
          return ChromeRepoTab(
            id: TabID("repo.\(name)"), title: name, aliases: index == 0 ? ["the api"] : [],
            badge: badges[index % badges.count])
        }
      })
    let log = Self.log
    registry.add(commands: [
      Command(
        id: "test.publish", title: "Publish", category: "Test", keys: ["<leader> x p"],
        risk: .outward
      ) { _ in
        log.published += 1
      },
      Command(id: "test.rename", title: "Rename", category: "Test", keys: ["<leader> x r"]) {
        context in
        log.names.append(
          await context.prompter.askText(TextRequest(title: "Rename", initial: "old")))
      },
      Command(id: "test.pick", title: "Pick a fruit", category: "Test", keys: ["<leader> x f"]) {
        context in
        let fruit = ["Apple", "Banana", "Blueberry", "Cherry"]
        log.picks.append(
          await context.prompter.choose(
            ChoiceRequest(
              title: "Fruit", choices: fruit.map { .init(value: $0.lowercased(), title: $0) })))
      },
      Command(id: "test.fail", title: "Fail", category: "Test", keys: ["<leader> x x"]) { _ in
        throw ChromeTestError.broken
      },
    ])
    registry.add(attentionSource: FakeAttentionSource(id: "chrome-attention"))
  }
}

enum ChromeTestError: Error, CustomStringConvertible {
  case broken
  var description: String { "the test command broke" }
}

/// The app chrome (P1-07) over a test module: tab bar, bars, Home, modals, toasts, tab
/// commands from keys and the palette.
@MainActor
@Suite(.serialized) struct ChromeTests {
  let host = UIHost(theme: .dark)
  let shell: AppShell
  let log = ChromeTestModule.log

  init() {
    shell = Self.makeShell(repos: ["api-server", "web", "infra", "docs"], host: host)
    log.published = 0
    log.names = []
    log.picks = []
  }

  static func makeShell(repos: [String], host: UIHost) -> AppShell {
    var environment = ModuleEnvironment(secrets: InMemorySecretStore())
    environment.repos = repos.map { RepoRoot(url: URL(filePath: "/src/\($0)")) }
    let shell = AppShell(modules: [ChromeTestModule.self], environment: environment, host: host) {}
    shell.toasts.sleep = { _ in try await Task.sleep(for: .seconds(3600)) }
    shell.start()
    return shell
  }

  var state: AppState { shell.core.state }

  /// Row `index` of the screen (0-based).
  func row(_ index: Int, width: Int = 80, height: Int = 24) -> String {
    let rows = host.plain(width: width, height: height)
      .split(separator: "\n", omittingEmptySubsequences: false)
    return rows.indices.contains(index) ? String(rows[index]) : ""
  }

  func post(_ title: String, _ priority: AttentionPriority) {
    state.post(
      AttentionItem(
        id: AttentionItemID(title), source: "chrome-attention", priority: priority, title: title))
  }

  // MARK: Layout

  @Test func chromeAtThreeSizes() {
    post("api-server wants to run npm install", .interrupt)
    post("Turn finished in web", .soon)
    post("Doc edited", .ambient)
    #expect(state.tabs.map(\.title) == ["Home", "api-server", "web", "infra", "docs"])
    #expect(state.selectedTabID == HomeTab.tabID)
    for (width, height) in [(80, 24), (120, 40), (200, 60)] {
      assertSnapshot(of: host, width: width, height: height, named: "\(width)x\(height)")
    }
    state.select("repo.api-server")
    assertSnapshot(of: host, width: 80, height: 24, named: "repo")
    assertSnapshot(of: host, width: 80, height: 24, format: .ansi(), named: "repo")
  }

  @Test func tabBarOverflowKeepsTheSelectedTabVisible() {
    let host = UIHost(theme: .dark)
    let shell = Self.makeShell(repos: (1...12).map { "repository-\($0)" }, host: host)
    let state = shell.core.state
    let firstLine = {
      host.plain(width: 80, height: 24).split(separator: "\n").first.map(String.init) ?? ""
    }
    #expect(firstLine().hasPrefix(" 1 Home  2 repository-1"))
    #expect(firstLine().hasSuffix("›"))
    state.select("repo.repository-9")
    #expect(firstLine().hasPrefix("‹"))
    #expect(firstLine().contains("repository-9"))
    assertSnapshot(of: host, width: 80, height: 24, named: "middle")
    state.select("repo.repository-12")
    #expect(firstLine().contains("repository-12"))
    #expect(!firstLine().hasSuffix("›"))
    shell.stop()
  }

  @Test func voiceBarStates() {
    let cases: [(VoiceStatus, String)] = [
      (VoiceStatus(), "○ voice off"),
      (VoiceStatus(mic: .idle), "○ idle"),
      (
        VoiceStatus(mic: .listening, transcript: "open the auth tic"),
        "● LISTENING  “open the auth tic”"
      ),
      (
        VoiceStatus(mic: .thinking, transcript: "open the auth ticket"),
        "◌ thinking…  “open the auth ticket”"
      ),
      (VoiceStatus(mic: .speaking, speaking: "api-server summary"), "▶ speaking"),
    ]
    for (status, expected) in cases {
      state.voice = status
      let bar = row(22)
      #expect(bar.contains(expected), "\(bar)")
    }
    #expect(host.plain(width: 80, height: 24).contains("⏵ api-server summary  queue: 0"))
    post("Something", .soon)
    #expect(host.plain(width: 80, height: 24).contains("queue: 1"))
  }

  @Test func hintBarShowsTheSelectedTabsCommands() {
    let hintLine = { row(23, width: 120) }
    #expect(hintLine() == " ^Space leader   ^P palette   ? help")
    state.select("repo.web")
    #expect(
      hintLine() == " ^Space leader   ^Space x p publish   ^Space x r rename   ^P palette   ? help")
  }

  // MARK: Tab commands

  @Test func tabSwitchingByKeysAndPalette() {
    host.type("\u{1B}2")  // Alt-2
    #expect(state.selectedTabID == "repo.api-server")
    host.type("\0")
    host.type("4")
    #expect(state.selectedTabID == "repo.infra")
    host.type("\0")
    host.type("t")
    host.type("n")
    #expect(state.selectedTabID == "repo.docs")

    host.type("\u{10}")  // Ctrl-P
    host.type("switch tab\r")
    assertSnapshot(of: host, width: 80, height: 24, named: "palette-tabs")
    host.type("the api\r")  // matches the alias in the choice title
    #expect(state.selectedTabID == "repo.api-server")
    #expect(!shell.keyboard.palette.isOpen)
  }

  @Test func closeAndReorderTabs() {
    host.type("\0")
    host.type("t")
    host.type("c")  // Home can't be closed: the key falls through
    #expect(state.tabs.count == 5)
    host.type("\0")
    host.type("3")
    host.type("\0")
    host.type("t")
    host.type("l")
    #expect(state.tabs.map(\.title) == ["Home", "api-server", "infra", "web", "docs"])
    #expect(state.selectedTabID == "repo.web")
    host.type("\0")
    host.type("t")
    host.type("c")
    #expect(state.tabs.map(\.title) == ["Home", "api-server", "infra", "docs"])
    #expect(state.selectedTabID == "repo.docs")
  }

  // MARK: Modals

  @Test func outwardCommandsAskFirstAndStartOnCancel() async {
    state.select("repo.web")
    host.type("\0")
    host.type("x")
    host.type("p")
    #expect(host.focus.focused == shell.modals.top?.cancelButtonID)
    assertSnapshot(of: host, width: 80, height: 24, named: "confirm")
    assertSnapshot(of: host, width: 80, height: 24, format: .ansi(), named: "confirm")
    host.type("\r")  // Cancel has focus
    #expect(await eventually { shell.modals.stack.isEmpty })
    #expect(log.published == 0)
    #expect(shell.toasts.toasts.isEmpty, "declining isn't a failure")
    #expect(host.focus.focused == HomeTab.inboxID || host.focus.focused == nil)

    host.type("\0")
    host.type("x")
    host.type("p")
    host.type("y")
    #expect(await eventually { log.published == 1 })

    host.type("\0")
    host.type("x")
    host.type("p")
    host.type("\u{1B}[C")  // ArrowRight: Confirm
    host.type("\r")
    #expect(await eventually { log.published == 2 })

    host.type("\0")
    host.type("x")
    host.type("p")
    host.type("\u{1B}")  // Esc
    #expect(await eventually { shell.modals.stack.isEmpty })
    host.type("n")  // no dialog: nothing to deny
    #expect(log.published == 2)
  }

  @Test func textPrompt() async {
    host.type("\0")
    host.type("x")
    host.type("r")
    #expect(host.text(of: shell.modals.top!.fieldID) == "old")
    host.type("\u{7F}\u{7F}\u{7F}new name")  // backspaces
    assertSnapshot(of: host, width: 80, height: 24, named: "text")
    host.type("\r")
    #expect(await eventually { log.names == ["new name"] })

    host.type("\0")
    host.type("x")
    host.type("r")
    host.type("\u{1B}")
    #expect(await eventually { log.names == ["new name", nil] })
  }

  @Test func listPicker() async {
    host.type("\0")
    host.type("x")
    host.type("f")
    assertSnapshot(of: host, width: 80, height: 24, named: "choices")
    host.type("b")
    #expect(shell.modals.top?.filteredChoices.map(\.title) == ["Banana", "Blueberry"])
    host.type("\u{1B}[B")  // ArrowDown
    assertSnapshot(of: host, width: 80, height: 24, named: "filtered")
    host.type("\r")
    #expect(await eventually { log.picks == ["blueberry"] })
  }

  @Test func stoppingCancelsOpenModals() async {
    host.type("\0")
    host.type("x")
    host.type("f")
    #expect(shell.modals.top != nil)
    shell.stop()
    #expect(await eventually { log.picks == [nil] })
  }

  // MARK: Toasts

  @Test func failuresAndNoticesShowAsToasts() async {
    host.type("\0")
    host.type("x")
    host.type("x")
    #expect(await eventually { shell.toasts.toasts.count == 1 })
    shell.modals.notify(Notice("Saved", kind: .success))
    assertSnapshot(of: host, width: 80, height: 24, named: "toasts")
    #expect(shell.toasts.toasts.map(\.notice.kind) == [.error, .success])
    #expect(shell.toasts.toasts.first?.notice.message == "the test command broke")
    for toast in shell.toasts.toasts { shell.toasts.dismiss(toast.id) }
    #expect(!host.plain(width: 80, height: 24).contains("Saved"))
  }

  @Test func toastsExpire() async {
    let toasts = ToastCenter()
    toasts.sleep = { _ in }
    toasts.show(Notice("gone soon"))
    #expect(await eventually { toasts.toasts.isEmpty })
    toasts.sleep = { _ in try await Task.sleep(for: .seconds(3600)) }
    for index in 1...5 { toasts.show(Notice("\(index)")) }
    #expect(toasts.toasts.map(\.notice.message) == ["3", "4", "5"], "at most three")
  }

  @Test func presenterPassesThePrompterContract() async {
    let host = UIHost(theme: .dark)
    let presenter = ModalPresenter(host: host)
    host.setContent { ModalsView(presenter: presenter) }
    host.render()
    await CommandPrompterContract.verify(
      presenter,
      answer: { answer in
        switch answer {
        case .confirm(let yes): presenter.answerConfirm(yes)
        case .text(let text): presenter.submit(text)
        case .choice(let value):
          let index = presenter.top?.filteredChoices.firstIndex { $0.value == value } ?? 0
          presenter.top?.list.selection = index
          presenter.submit("")
        case .cancel: presenter.cancelTop()
        }
      },
      pending: { presenter.stack.count })
  }
}
