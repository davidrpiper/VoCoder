import Foundation
import Testing
import VoCoderFakes
import VoCoderTestSupport

@testable import VoCoderCore

/// A check that never finishes on its own (ignores cancellation).
struct StuckCheck: DoctorCheck {
  let id: ProviderID = "stuck"
  let title = "Stuck"
  func run() async -> DoctorResult {
    while true { try? await Task.sleep(for: .seconds(60)) }
  }
}

@Suite struct DoctorTests {
  @Test func reportRendersOneLinePerCheckWithHints() async {
    let report = await Doctor.run([
      ("core", FakeDoctorCheck(id: "a", title: "Config", result: .ok("fine"))),
      (
        "linear",
        FakeDoctorCheck(
          id: "b", title: "Linear API", result: .failure("401\nkey revoked", hint: "re-auth"))
      ),
      ("app", FakeDoctorCheck(id: "c", title: "Terminal", result: .warning("tmux", hint: "don't"))),
      ("app", FakeDoctorCheck(id: "d", title: "Mouse", result: .skipped("n/a"))),
    ])
    #expect(report.worst == .failure)
    #expect(
      report.rendered() == """
        ✓ Config      fine
        ✗ Linear API  401 [linear]
                      key revoked
                      → re-auth
        ! Terminal    tmux
                      → don't
        – Mouse       n/a

        1 failure, 1 warning, 1 skipped, 1 ok
        """)
    #expect(report.rendered(colors: true).contains("\u{1B}[31m✗\u{1B}[0m"))
  }

  @Test func emptyReportIsOK() async {
    #expect(await Doctor.run([]).worst == .ok)
  }

  @Test func slowChecksFailAfterTheTimeout() async {
    let report = await Doctor.run(
      [("core", StuckCheck()), ("core", FakeDoctorCheck())], timeout: .milliseconds(50))
    #expect(report.entries.map(\.result.status) == [.failure, .ok])
    #expect(report.entries.first?.result.message.contains("didn't finish") == true)
  }

  @Test func fakeAndClosureChecksPassTheContract() async {
    await DoctorCheckContract.verify(FakeDoctorCheck())
    await DoctorCheckContract.verify(
      FakeDoctorCheck(result: .warning("w", hint: "fix it")))
    await DoctorCheckContract.verify(ClosureDoctorCheck(id: "x", title: "X") { .ok("x") })
  }

  @MainActor
  @Test func configCheck() async {
    let file = URL(filePath: "/tmp/vocoder.toml")
    let missing = ConfigLoadResult(
      config: AppConfig(), errors: [], exists: false, displayPath: "~/c.toml")
    let broken = ConfigLoader.parse("[ui]\ntheme = 1\n", file: file, modules: [])
    let valid = ConfigLoader.parse("[ui]\ntheme = \"dark\"\n", file: file, modules: [])
    #expect(await CoreDoctorChecks.config(missing).run().status == .warning)
    let failure = await CoreDoctorChecks.config(broken).run()
    #expect(failure.status == .failure)
    #expect(failure.message.contains("ui.theme: expected a string"))
    #expect(await CoreDoctorChecks.config(valid).run() == .ok("/tmp/vocoder.toml (0 repos)"))
    for check in [missing, broken, valid].map(CoreDoctorChecks.config) {
      await DoctorCheckContract.verify(check)
    }
  }

  @Test func moduleAndKeymapChecks() async {
    let issues = [ModuleIssue(module: "linear", message: "failed to start: offline")]
    let failing = await CoreDoctorChecks.modules(loaded: ["git"], issues: issues).run()
    #expect(failing.status == .failure)
    #expect(failing.message.contains("linear: failed to start: offline"))
    #expect(await CoreDoctorChecks.modules(loaded: ["git"], issues: []).run() == .ok("git"))
    let keymap = await CoreDoctorChecks.keymap(issues: ["keys for unknown command 'x'"]).run()
    #expect(keymap.status == .warning)
    #expect(await CoreDoctorChecks.keymap(issues: []).run().status == .ok)
    await DoctorCheckContract.verify(CoreDoctorChecks.modules(loaded: [], issues: issues))
    await DoctorCheckContract.verify(CoreDoctorChecks.keymap(issues: ["x"]))
  }

  @Test func secretsCheckReportsMissingOnesPerModule() async throws {
    let spec = SecretSpec(name: "api-key", title: "API key", help: "somewhere")
    let store = InMemorySecretStore()
    let modules: [(id: ModuleID, specs: [SecretSpec])] = [
      ("linear", [spec]), ("notion", [spec]), ("git", []),
    ]
    let missing = await CoreDoctorChecks.secrets(modules: modules, store: store).run()
    #expect(missing.status == .warning)
    #expect(missing.message == "linear: API key not set\nnotion: API key not set")
    #expect(missing.hint?.contains("`vocoder auth linear`, `vocoder auth notion`") == true)
    try store.setSecret("k", for: SecretKey(module: "linear", name: "api-key"))
    try store.setSecret("k", for: SecretKey(module: "notion", name: "api-key"))
    #expect(await CoreDoctorChecks.secrets(modules: modules, store: store).run() == .ok("2 set"))
    #expect(
      await CoreDoctorChecks.secrets(modules: [("git", [])], store: store).run()
        == .ok("no enabled module needs one"))
    await DoctorCheckContract.verify(
      CoreDoctorChecks.secrets(modules: modules, store: InMemorySecretStore()))
  }

  @MainActor
  @Test func doctorChecksAreAnExtensionPoint() {
    var registry = ModuleRegistry(module: "a")
    registry.add(doctorCheck: FakeDoctorCheck(id: "a.cli"))
    registry.currentModule = "b"
    registry.add(doctorCheck: FakeDoctorCheck(id: "a.cli"))
    #expect(registry.doctorChecks.count == 1)
    #expect(registry.owner(of: "a.cli", in: .doctorChecks) == "a")
    #expect(registry.issues.map(\.module) == ["b"])
  }
}

@Suite struct SecretTests {
  let spec = SecretSpec(name: "api-key", title: "API key", help: "settings")
  let other = SecretSpec(name: "workspace", title: "Workspace", help: "url")

  func temporaryLog() -> (Log, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "vocoder-secret-log-\(UUID().uuidString)")
    let sink = FileLogSink(directory: directory)
    return (Log(category: "secrets", sink: sink), sink.currentFile)
  }

  @Test func setupStoresAnswersAndKeepsBlankOnes() throws {
    let store = InMemorySecretStore()
    let key = SecretKey(module: "linear", name: "api-key")
    let outcomes = try SecretSetup.store([spec, other], module: "linear", in: store) {
      $0.name == "api-key" ? "  lin_api_123\n" : ""
    }
    #expect(outcomes.map(\.outcome) == [.stored, .unchanged])
    #expect(try store.secret(for: key) == "lin_api_123")
    #expect(try SecretSetup.missing([spec, other], module: "linear", in: store) == [other])
    let removed = try SecretSetup.remove([spec], module: "linear", from: store)
    #expect(removed.map(\.outcome) == [.removed])
    #expect(try store.secret(for: key) == nil)
  }

  @Test func secretValuesNeverReachTheLog() throws {
    let (log, file) = temporaryLog()
    let value = "lin_api_SECRET_\(UUID().uuidString)"
    _ = try SecretSetup.store([spec], module: "linear", in: InMemorySecretStore(), log: log) { _ in
      value
    }
    _ = try SecretSetup.remove([spec], module: "linear", from: InMemorySecretStore(), log: log)
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(text.contains("secret stored for linear/api-key"))
    #expect(text.contains("secret removed for linear/api-key"))
    #expect(!text.contains(value))
  }

  /// Uses the real login keychain (adds and deletes an item under `dev.vocoder.test.*`), so it
  /// only runs with `VOCODER_KEYCHAIN_TESTS=1`.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["VOCODER_KEYCHAIN_TESTS"] == "1"))
  func keychainStorePassesTheContract() throws {
    try SecretStoreContract.verify(KeychainSecretStore(servicePrefix: "dev.vocoder.test"))
  }

  @Test func keychainServiceNames() {
    let store = KeychainSecretStore()
    #expect(
      store.service(for: SecretKey(module: "linear", name: "api-key")) == "dev.vocoder.linear")
    #expect(
      KeychainError(operation: "read x", status: errSecItemNotFound).description
        .hasPrefix("Keychain: couldn't read x: "))
  }
}
