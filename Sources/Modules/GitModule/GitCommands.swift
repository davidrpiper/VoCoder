import Foundation
import VoCoderCore

/// Git's commands (`<leader> g …`). They act on the selected tab's repository; without one, on
/// the only configured repository, or they ask which one.
public enum GitCommandIDs {
  public static let refresh: CommandID = "git.refresh"
  public static let checkoutBranch: CommandID = "git.checkoutBranch"
  public static let commit: CommandID = "git.commit"
}

@MainActor
struct GitCommands {
  let repos: [RepoRoot]
  let sourceControl: any SourceControl

  /// The checkout list's entry for a new branch (not a valid branch name).
  static let newBranch = "\u{1}new"

  var all: [Command] {
    let repos = repos
    let available: Command.Availability = { context in
      context.selectedTab?.repo != nil || !repos.isEmpty
    }
    let repoParameter = CommandParameter(
      "repo", title: "Repository", kind: .choice { Self.repoChoices(repos, $0) }, isOptional: true)
    return [
      Command(
        id: GitCommandIDs.refresh, title: "Git status", category: "Git", keys: ["<leader> g r"],
        voicePhrases: ["git status", "refresh git", "what changed"], params: [repoParameter],
        isAvailable: available
      ) { context in
        guard let repository = try await repository(for: context) else { return }
        let status = try await repository.status()
        context.say(status.summary)
        context.prompter.notify(Notice(status.summary))
      },
      Command(
        id: GitCommandIDs.checkoutBranch, title: "Check out branch", category: "Git",
        keys: ["<leader> g b"], voicePhrases: ["check out a branch", "switch branch"],
        params: [
          CommandParameter("branch", title: "Branch", isOptional: true), repoParameter,
        ],
        risk: .reversible, isAvailable: available
      ) { context in
        try await checkout(context)
      },
      Command(
        id: GitCommandIDs.commit, title: "Commit", category: "Git", keys: ["<leader> g c"],
        voicePhrases: ["commit it", "commit"],
        params: [CommandParameter("message", title: "Commit message"), repoParameter],
        risk: .outward, isAvailable: available
      ) { context in
        try await commit(context)
      },
    ]
  }

  // MARK: Commands

  private func checkout(_ context: CommandContext) async throws {
    guard let repository = try await repository(for: context) else { return }
    let previous = try await repository.status().branch
    let branches = try await repository.branches()
    var name = context.arguments.text("branch")?.trimmingCharacters(in: .whitespaces)
    if name == nil || name == "" {
      let choices =
        branches.map {
          CommandParameter.Choice(
            value: $0.name, title: $0.name + ($0.isCurrent ? " (current)" : ""))
        } + [CommandParameter.Choice(value: Self.newBranch, title: "+ New branch…")]
      name = await context.prompter.choose(
        ChoiceRequest(title: "Check out branch", choices: choices))
    }
    guard var name else { return }
    var create = false
    if name == Self.newBranch {
      guard
        let entered = await context.prompter.askText(
          TextRequest(title: "New branch", placeholder: "feature/name")),
        !entered.trimmingCharacters(in: .whitespaces).isEmpty
      else { return }
      name = entered.trimmingCharacters(in: .whitespaces)
      create = true
    } else if !branches.contains(where: { $0.name == name }) {
      let confirmed = await context.prompter.confirm(
        ConfirmRequest(
          title: "Create branch \(name)?", message: "There is no branch named \(name).",
          confirmTitle: "Create", confirmIsDefault: true))
      guard confirmed else { return }
      create = true
    } else if name == previous {
      context.say("Already on \(name)")
      return
    }

    if create {
      try await repository.createBranch(name, checkout: true)
    } else {
      try await repository.checkout(name)
    }
    context.say(create ? "Created and switched to \(name)" : "Switched to \(name)")
    if let previous, previous != name {
      context.offerUndo(
        UndoAction(title: "Switch back to \(previous)") {
          try await repository.checkout(previous)
        })
    }
  }

  private func commit(_ context: CommandContext) async throws {
    let message = (context.arguments.text("message") ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else {
      throw CommandError.invalidArgument(GitCommandIDs.commit, parameter: "message")
    }
    guard let repository = try await repository(for: context) else { return }
    let status = try await repository.status()
    guard status.conflicted.isEmpty else {
      let count = status.conflicted.count
      throw SourceControlError.failed(
        operation: "Commit",
        message: "resolve \(count) conflicted \(count == 1 ? "file" : "files") first")
    }
    if status.staged.isEmpty {
      guard !status.isClean else {
        context.prompter.notify(Notice("Nothing to commit"))
        context.say("Nothing to commit")
        return
      }
      let count = status.files.count
      let files = "\(count) changed \(count == 1 ? "file" : "files")"
      let confirmed = await context.prompter.confirm(
        ConfirmRequest(
          title: "Stage all changes?", message: "Nothing is staged. Stage and commit all \(files)?",
          confirmTitle: "Stage all", confirmIsDefault: true))
      guard confirmed else { return }
      try await repository.stage([])
    }
    let id = try await repository.commit(message: message)
    let subject = message.split(separator: "\n").first.map(String.init) ?? message
    context.prompter.notify(Notice("Committed \(id.short): \(subject)", kind: .success))
    context.say("Committed \(id.short)")
  }

  // MARK: Target repository

  /// The repository the command acts on, or nil when the user cancelled the choice.
  private func repository(for context: CommandContext) async throws -> (any Repository)? {
    guard let root = await target(context) else { return nil }
    return try await sourceControl.repository(at: root.url)
  }

  private func target(_ context: CommandContext) async -> RepoRoot? {
    let candidates = Self.candidates(repos, context)
    if let path = context.arguments.text("repo") {
      return candidates.first { $0.url.path == path }
    }
    if let repo = context.selectedTab?.repo { return repo }
    if candidates.count <= 1 { return candidates.first }
    guard
      let path = await context.prompter.choose(
        ChoiceRequest(title: "Repository", choices: Self.repoChoices(repos, context)))
    else { return nil }
    return candidates.first { $0.url.path == path }
  }

  /// The configured repositories, plus the selected tab's if it isn't one of them.
  static func candidates(_ repos: [RepoRoot], _ context: CommandContext) -> [RepoRoot] {
    guard let tabRepo = context.selectedTab?.repo, !repos.contains(tabRepo) else { return repos }
    return repos + [tabRepo]
  }

  static func repoChoices(_ repos: [RepoRoot], _ context: CommandContext)
    -> [CommandParameter.Choice]
  {
    candidates(repos, context).map { repo in
      let aliases = repo.aliases.isEmpty ? "" : " (" + repo.aliases.joined(separator: ", ") + ")"
      return CommandParameter.Choice(value: repo.url.path, title: repo.name + aliases)
    }
  }
}
