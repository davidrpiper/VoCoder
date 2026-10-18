// Git for repo tabs (DESIGN §3.2, ADR 0011): the `SourceControl` provider over the `git` CLI,
// the git commands and the doctor check. Depends on Core only; never on other modules.
import Foundation
import VoCoderCore

/// Registers git as the source control provider, its commands and its doctor check.
public final class GitModule: VoCoderModule {
  public static let id: ModuleID = "git"
  /// `git switch` (2.23) is the newest command used; porcelain v2 status needs 2.11.
  public nonisolated static let minimumGitVersion = CLIVersion("2.23")!

  let repos: [RepoRoot]
  public let sourceControl: GitSourceControl

  public init(context: ModuleContext) {
    repos = context.repos
    sourceControl = GitSourceControl()
  }

  public func register(into registry: inout ModuleRegistry) {
    registry.add(sourceControl: sourceControl)
    registry.add(commands: GitCommands(repos: repos, sourceControl: sourceControl).all)
    registry.add(doctorCheck: GitCLICheck(minimum: Self.minimumGitVersion))
  }
}

/// `vocoder doctor`: git is installed and new enough.
public struct GitCLICheck: DoctorCheck {
  public let id: ProviderID = "git.cli"
  public let title = "Git"
  let minimum: CLIVersion
  let locate: @Sendable () -> URL?
  let versionOutput: @Sendable (URL) async -> String?

  public init(
    minimum: CLIVersion,
    locate: @escaping @Sendable () -> URL? = { GitRunner.findExecutable() },
    versionOutput: @escaping @Sendable (URL) async -> String? = { executable in
      let output = try? await GitRunner(executable: executable, timeout: .seconds(10))
        .run(["--version"], in: nil, operation: "git --version")
      return output?.status == 0 ? output?.text : nil
    }
  ) {
    self.minimum = minimum
    self.locate = locate
    self.versionOutput = versionOutput
  }

  public func run() async -> DoctorResult {
    guard let url = locate() else {
      return .failure(
        "`git` not found on PATH",
        hint: "install it: `xcode-select --install` or `brew install git`")
    }
    guard let output = await versionOutput(url), let version = CLIVersion(versionOutput: output)
    else {
      return .failure(
        "\(url.path) --version gave no version", hint: "check `git --version` in a shell")
    }
    guard version >= minimum else {
      return .failure(
        "\(version) is older than \(minimum)", hint: "update git (`brew install git`)")
    }
    return .ok("\(version) at \(url.path)")
  }
}
