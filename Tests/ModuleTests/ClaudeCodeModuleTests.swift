import ClaudeCodeModule
import Foundation
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
    let result = load("[claude-code]\nmcp_servers = \"user\"\n")
    #expect(result.errors.isEmpty)
    let environment = result.config.environment(
      for: [ClaudeCodeModule.self], secrets: InMemorySecretStore())
    let loaded = ModuleLoader.load([ClaudeCodeModule.self], environment: environment)
    let module = try #require(loaded.modules.first as? ClaudeCodeModule)
    #expect(module.config.mcpServers == .user)
  }

  @Test func configDefaultsAndErrors() {
    #expect(load("").config.sections.isEmpty)
    let bad = load("[claude-code]\nmcp_servers = \"all\"\nmcp = 1\n")
    #expect(
      bad.errors.map(\.description) == [
        "/tmp/config.toml:2: claude-code.mcp_servers: 'all' isn't one of: none, user",
        "/tmp/config.toml:3: claude-code.mcp: unknown key\n    allowed here: mcp_servers",
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

  @Test func registersTheCLICheck() {
    let loaded = ModuleLoader.load(
      [ClaudeCodeModule.self], environment: ModuleEnvironment(secrets: InMemorySecretStore()))
    #expect(loaded.registry.doctorChecks.map(\.id) == ["claude-code.cli"])
  }
}
