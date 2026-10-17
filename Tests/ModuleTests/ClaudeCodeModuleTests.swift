import ClaudeCodeModule
import Foundation
import Synchronization
import Testing
import VoCoderCore
import VoCoderFakes
import VoCoderTestSupport

@MainActor
@Suite struct ClaudeCodeModuleTests {
  func load(_ text: String) -> ConfigLoadResult {
    ConfigLoader.parse(
      text, file: URL(filePath: "/tmp/config.toml"), modules: [ClaudeCodeModule.self])
  }

  @Test func configSection() throws {
    let result = load("[claude-code]\nmcp_servers = \"user\"\nmodel = \"sonnet\"\n")
    #expect(result.errors.isEmpty)
    let environment = result.config.environment(
      for: [ClaudeCodeModule.self], secrets: InMemorySecretStore())
    let loaded = ModuleLoader.load([ClaudeCodeModule.self], environment: environment)
    let module = try #require(loaded.modules.first as? ClaudeCodeModule)
    #expect(module.config.mcpServers == .user)
    #expect(module.config.model == "sonnet")
  }

  @Test func configDefaultsAndErrors() {
    #expect(load("").config.sections.isEmpty)
    let bad = load("[claude-code]\nmcp_servers = \"all\"\nmcp = 1\n")
    #expect(
      bad.errors.map(\.description) == [
        "/tmp/config.toml:2: claude-code.mcp_servers: 'all' isn't one of: none, user",
        "/tmp/config.toml:3: claude-code.mcp: unknown key\n    allowed here: mcp_servers, model",
      ])
  }

  @Test func versions() {
    #expect(CLIVersion(versionOutput: "2.1.302 (Claude Code)") == CLIVersion("2.1.302"))
    #expect(CLIVersion("2.1.302")! < CLIVersion("2.1.1000")!)
    #expect(CLIVersion("2.2")! > CLIVersion("2.1.999")!)
    #expect(CLIVersion("2.1") == CLIVersion("2.1.0"))
    #expect(CLIVersion("x.1") == nil)
    #expect(CLIVersion(versionOutput: "") == nil)
  }

  @Test func cliCheck() async {
    let minimum = CLIVersion("2.1.302")!
    let claude = URL(filePath: "/opt/bin/claude")
    func check(found: Bool = true, output: String?) -> ClaudeCLICheck {
      ClaudeCLICheck(
        minimum: minimum, locate: { found ? claude : nil }, versionOutput: { _ in output })
    }
    #expect(
      await check(output: "2.1.400 (Claude Code)\n").run() == .ok("2.1.400 at /opt/bin/claude"))
    let old = await check(output: "2.0.9 (Claude Code)").run()
    #expect(old.status == .failure)
    #expect(old.hint == "update it: `claude update`")
    #expect(await check(found: false, output: nil).run().status == .failure)
    #expect(await check(output: "oops").run().status == .failure)
    for output in ["2.1.400", "2.0.0", "junk"] {
      await DoctorCheckContract.verify(check(output: output))
    }
    await DoctorCheckContract.verify(check(found: false, output: nil))
  }

  @Test func findsTheExecutableOnPathOrInFallbacks() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "vocoder-claude-\(UUID().uuidString)")
    let bin = directory.appending(path: "bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let claude = bin.appending(path: "claude")
    try Data("#!/bin/sh\n".utf8).write(to: claude)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
    let found = ClaudeCLICheck.findExecutable(
      environment: ["PATH": "/nonexistent:\(bin.path)"], home: directory)
    #expect(found?.path == claude.path)
    let local = directory.appending(path: ".local/bin")
    try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: claude, to: local.appending(path: "claude"))
    #expect(
      ClaudeCLICheck.findExecutable(environment: ["PATH": ""], home: directory)?.lastPathComponent
        == "claude")
  }

  @Test func registersTheBackendAndTheCLICheck() async {
    let loaded = ModuleLoader.load(
      [ClaudeCodeModule.self], environment: ModuleEnvironment(secrets: InMemorySecretStore()))
    #expect(loaded.registry.doctorChecks.map(\.id) == ["claude-code.cli"])
    #expect(loaded.registry.agents.map(\.id) == ["claude-code"])
    for agent in loaded.registry.agents { AgentBackendContract.verify(agent) }
    await AgentBackendContract.verifyStub(CodexBackend())
    await AgentBackendContract.verifyStub(GeminiBackend())
  }

  @Test func arguments() {
    let fresh = ClaudeLaunch.arguments(config: ClaudeCodeConfig(), model: nil, resume: nil)
    #expect(fresh.prefix(3) == ["-p", "--input-format", "stream-json"])
    #expect(fresh.contains("--strict-mcp-config"))
    #expect(!fresh.contains("--model"))
    let tools = fresh[fresh.firstIndex(of: "--tools")! + 1]
    #expect(tools.contains("TaskCreate"))
    let spoken = fresh[fresh.firstIndex(of: "--append-system-prompt")! + 1]
    #expect(spoken.contains("<spoken>"))

    let configured = ClaudeLaunch.arguments(
      config: ClaudeCodeConfig(mcpServers: .user, model: "sonnet"), model: nil, resume: "s-9")
    #expect(!configured.contains("--strict-mcp-config"))
    #expect(configured.suffix(4) == ["--model", "sonnet", "--resume", "s-9"])
    let overridden = ClaudeLaunch.arguments(
      config: ClaudeCodeConfig(model: "sonnet"), model: "haiku", resume: nil)
    #expect(overridden.suffix(2) == ["--model", "haiku"])
  }

  @Test func environmentIsSanitized() {
    let environment = ClaudeLaunch.sanitized([
      "PATH": "/bin", "HOME": "/Users/x", "CLAUDECODE": "1", "CLAUDE_PID": "1", "AI_AGENT": "a",
      "CLAUDE_CODE_ENTRYPOINT": "cli", "CLAUDE_CODE_SESSION_ID": "s",
      "CLAUDE_CODE_USE_BEDROCK": "1", "ANTHROPIC_API_KEY": "k",
    ])
    #expect(
      environment == [
        "PATH": "/bin", "HOME": "/Users/x", "CLAUDE_CODE_USE_BEDROCK": "1",
        "ANTHROPIC_API_KEY": "k",
      ])
  }

  @Test func startChecksTheExecutableAndItsVersionOnce() async throws {
    let options = AgentSessionOptions(repo: URL(filePath: "/tmp"))
    let missing = ClaudeCodeBackend(locate: { nil })
    await #expect(throws: AgentError.executableNotFound("claude")) {
      _ = try await missing.startSession(options)
    }
    let old = ClaudeCodeBackend(
      locate: { URL(filePath: "/opt/bin/claude") }, versionOutput: { _ in "2.0.1 (Claude Code)" })
    await #expect(throws: AgentError.unsupportedVersion(found: "2.0.1", minimum: "2.1.302")) {
      _ = try await old.startSession(options)
    }

    let checks = Mutex(0)
    let launched = Mutex(0)
    let counting = ClaudeCodeBackend(
      locate: { URL(filePath: "/opt/bin/claude") },
      versionOutput: { _ in
        checks.withLock { $0 += 1 }
        return "2.1.400"
      },
      launcher: { _ in
        launched.withLock { $0 += 1 }
        throw AgentError.launchFailed("test")
      })
    for _ in 0..<2 {
      await #expect(throws: AgentError.launchFailed("test")) {
        _ = try await counting.startSession(options)
      }
    }
    #expect(checks.withLock { $0 } == 1)
    #expect(launched.withLock { $0 } == 2)
  }
}
