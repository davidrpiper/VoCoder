import Foundation
import Testing
import VoCoderCore
import VoCoderFakes

@testable import GitModule

/// Git's commands over the fake source control, through the dispatcher.
@MainActor
@Suite struct GitCommandTests {
  let state = AppState()
  let dispatcher: CommandDispatcher
  let prompter = FakePrompter()
  let sourceControl = FakeSourceControl()
  let api = RepoRoot(url: URL(filePath: "/work/api"), aliases: ["the api"])
  let web = RepoRoot(url: URL(filePath: "/work/web"))
  let apiRepository: FakeRepository
  let webRepository: FakeRepository

  init() {
    apiRepository = sourceControl.makeRepository(at: api.url, files: ["a.txt": "a\n"])
    webRepository = sourceControl.makeRepository(at: web.url, files: ["w.txt": "w\n"])
    dispatcher = CommandDispatcher(state: state)
    dispatcher.prompter = prompter
  }

  func register(repos: [RepoRoot]) {
    dispatcher.register(GitCommands(repos: repos, sourceControl: sourceControl).all)
  }

  func openRepoTab(_ repo: RepoRoot) {
    state.open(FakeTab(id: TabID("repo.\(repo.name)"), title: repo.name, repo: repo))
  }

  @Test func unavailableWithoutRepositories() {
    register(repos: [])
    state.open(FakeTab(id: "other"))
    #expect(!dispatcher.isAvailable(GitCommandIDs.refresh))
    openRepoTab(api)
    state.select("repo.api")
    #expect(dispatcher.isAvailable(GitCommandIDs.refresh))
  }

  @Test func refreshSaysTheStatus() async throws {
    register(repos: [api])
    apiRepository.write("a.txt", "changed\n")
    let outcome = try await dispatcher.run(GitCommandIDs.refresh)
    #expect(outcome.spoken == "main, 1 changed file")
    #expect(prompter.notices == [Notice("main, 1 changed file")])
  }

  @Test func theSelectedTabsRepositoryWins() async throws {
    register(repos: [api, web])
    openRepoTab(web)
    webRepository.write("new.txt", "n\n")
    let outcome = try await dispatcher.run(GitCommandIDs.refresh)
    #expect(outcome.spoken == "main, 1 changed file")
    #expect(prompter.requests.isEmpty)
  }

  @Test func severalRepositoriesAsk() async throws {
    register(repos: [api, web])
    state.open(FakeTab(id: "home"))
    prompter.autoAnswer = { _ in .choice(web.url.path) }
    webRepository.write("w.txt", nil)
    let outcome = try await dispatcher.run(GitCommandIDs.refresh)
    #expect(outcome.spoken == "main, 1 changed file")
    #expect(
      prompter.requests == [
        .choice(
          ChoiceRequest(
            title: "Repository",
            choices: [
              .init(value: "/work/api", title: "api (the api)"),
              .init(value: "/work/web", title: "web"),
            ]))
      ])
    // Cancelling the choice does nothing.
    prompter.autoAnswer = { _ in .cancel }
    #expect(try await dispatcher.run(GitCommandIDs.refresh).spoken == nil)
    // An explicit repo argument doesn't ask.
    let explicit = try await dispatcher.run(GitCommandIDs.refresh, arguments: ["repo": "/work/api"])
    #expect(explicit.spoken == "main, clean")
  }

  @Test func checkoutFromTheListWithUndo() async throws {
    register(repos: [api])
    try await apiRepository.createBranch("feature", checkout: false)
    prompter.autoAnswer = { _ in .choice("feature") }
    let outcome = try await dispatcher.run(GitCommandIDs.checkoutBranch)
    #expect(outcome.spoken == "Switched to feature")
    guard case .choice(let request) = prompter.requests.first else {
      Issue.record("no branch list")
      return
    }
    #expect(request.choices.map(\.title) == ["feature", "main (current)", "+ New branch…"])
    #expect(try await apiRepository.status().branch == "feature")

    let undo = try #require(outcome.undo)
    #expect(undo.title == "Switch back to main")
    try await undo.perform()
    #expect(try await apiRepository.status().branch == "main")
  }

  @Test func checkoutCreatesBranches() async throws {
    register(repos: [api])
    prompter.autoAnswer = { request in
      if case .choice = request { return .choice(GitCommands.newBranch) }
      return .text("feature/new")
    }
    var outcome = try await dispatcher.run(GitCommandIDs.checkoutBranch)
    #expect(outcome.spoken == "Created and switched to feature/new")
    #expect(try await apiRepository.status().branch == "feature/new")

    // A name that doesn't exist yet asks before creating it (voice: "check out branch x").
    prompter.autoAnswer = { _ in .confirm(true) }
    outcome = try await dispatcher.run(GitCommandIDs.checkoutBranch, arguments: ["branch": "spike"])
    #expect(outcome.spoken == "Created and switched to spike")
    #expect(outcome.undo?.title == "Switch back to feature/new")

    outcome = try await dispatcher.run(GitCommandIDs.checkoutBranch, arguments: ["branch": "spike"])
    #expect(outcome.spoken == "Already on spike")

    prompter.autoAnswer = { _ in .confirm(false) }
    outcome = try await dispatcher.run(GitCommandIDs.checkoutBranch, arguments: ["branch": "no"])
    #expect(outcome.spoken == nil)
    #expect(try await apiRepository.branches().map(\.name) == ["feature/new", "main", "spike"])
  }

  @Test func checkoutErrorsReachTheCaller() async throws {
    register(repos: [api])
    prompter.autoAnswer = { _ in .confirm(true) }
    await #expect(throws: SourceControlError.invalidBranchName("bad name")) {
      try await dispatcher.run(GitCommandIDs.checkoutBranch, arguments: ["branch": "bad name"])
    }
  }

  @Test func commitCommitsTheIndex() async throws {
    register(repos: [api])
    apiRepository.write("a.txt", "b\n")
    apiRepository.write("other.txt", "o\n")
    try await apiRepository.stage(["a.txt"])
    let outcome = try await dispatcher.run(
      GitCommandIDs.commit, arguments: ["message": "Change a\n\nBody"])
    #expect(outcome.spoken == "Committed 0000002")
    #expect(prompter.notices == [Notice("Committed 0000002: Change a", kind: .success)])
    #expect(apiRepository.commitMessages.last == "Change a\n\nBody")
    #expect(try await apiRepository.status().files.map(\.path) == ["other.txt"])
  }

  @Test func commitOffersToStageEverything() async throws {
    register(repos: [api])
    apiRepository.write("a.txt", "b\n")
    apiRepository.write("other.txt", "o\n")
    prompter.autoAnswer = { _ in .confirm(true) }
    let outcome = try await dispatcher.run(GitCommandIDs.commit, arguments: ["message": "All"])
    #expect(outcome.spoken == "Committed 0000002")
    #expect(
      prompter.requests == [
        .confirm(
          ConfirmRequest(
            title: "Stage all changes?",
            message: "Nothing is staged. Stage and commit all 2 changed files?",
            confirmTitle: "Stage all", confirmIsDefault: true))
      ])
    #expect(try await apiRepository.status().isClean)

    // Declined: nothing happens.
    apiRepository.write("a.txt", "c\n")
    prompter.autoAnswer = { _ in .confirm(false) }
    #expect(
      try await dispatcher.run(GitCommandIDs.commit, arguments: ["message": "No"]).spoken == nil)
    #expect(apiRepository.commitMessages == ["Initial commit", "All"])
  }

  @Test func commitWithNothingToCommit() async throws {
    register(repos: [api])
    let outcome = try await dispatcher.run(GitCommandIDs.commit, arguments: ["message": "Empty"])
    #expect(outcome.spoken == "Nothing to commit")
    await #expect(throws: CommandError.invalidArgument(GitCommandIDs.commit, parameter: "message"))
    {
      try await dispatcher.run(GitCommandIDs.commit, arguments: ["message": "  \n"])
    }
  }

  @Test func commitIsOutward() {
    let commands = GitCommands(repos: [api], sourceControl: sourceControl).all
    let risks = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0.risk) })
    #expect(risks[GitCommandIDs.commit] == .outward)
    #expect(risks[GitCommandIDs.checkoutBranch] == .reversible)
    #expect(risks[GitCommandIDs.refresh] == .readOnly)
    #expect(commands.allSatisfy { !$0.keys.isEmpty && !$0.voicePhrases.isEmpty })
  }

  @Test func moduleRegistersGit() throws {
    let loaded = ModuleLoader.load(
      [GitModule.self],
      environment: ModuleEnvironment(secrets: InMemorySecretStore(), repos: [api]))
    #expect(loaded.registry.sourceControl.map(\.id) == ["git"])
    #expect(loaded.registry.owner(of: "git", in: .sourceControl) == "git")
    #expect(
      Set(loaded.registry.commands.map(\.id))
        == [GitCommandIDs.refresh, GitCommandIDs.checkoutBranch, GitCommandIDs.commit])
    #expect(loaded.registry.doctorChecks.map(\.id) == ["git.cli"])
  }
}
