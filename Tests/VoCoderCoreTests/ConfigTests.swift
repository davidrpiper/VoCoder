import Foundation
import Testing
import VoCoderFakes

@testable import VoCoderCore

/// A module with a config section, as a real one declares it.
final class SettingsModule: VoCoderModule {
  struct Settings: ConfigSection, Equatable {
    enum Mode: String, Decodable { case fast, careful }
    var mode: Mode
    var retries: Int?

    static let keys: [String]? = ["mode", "retries"]
  }

  static let id: ModuleID = "configured"
  static let configSection: (any ConfigSection.Type)? = Settings.self
  static let secrets = [SecretSpec(name: "token", title: "Token", help: "anywhere")]

  let settings: Settings?

  init(context: ModuleContext) { settings = context.config(Settings.self) }
  func register(into registry: inout ModuleRegistry) {}
}

final class NoSettingsModule: VoCoderModule {
  static let id: ModuleID = "plain"
  init(context: ModuleContext) {}
  func register(into registry: inout ModuleRegistry) {}
}

@MainActor
@Suite struct ConfigTests {
  let directory: URL
  let modules: [any VoCoderModule.Type] = [SettingsModule.self, NoSettingsModule.self]

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appending(path: "vocoder-config-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory.appending(path: "repos/api"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: directory.appending(path: "repos/web"), withIntermediateDirectories: true)
    try Data().write(to: directory.appending(path: "repos/file.txt"))
  }

  var file: URL { directory.appending(path: "config.toml") }

  func parse(_ text: String) -> ConfigLoadResult {
    ConfigLoader.parse(text, file: file, modules: modules, home: directory)
  }

  func messages(_ result: ConfigLoadResult) -> [String] { result.errors.map(\.description) }

  @Test func templateLoadsCleanly() {
    let result = parse(ConfigTemplate.text)
    #expect(result.errors.isEmpty, "\(messages(result))")
    #expect(result.config.theme == .auto)
    #expect(result.config.keys.leader == KeyChord("ctrl+space"))
  }

  @Test func fullConfig() {
    let result = parse(
      """
      [[repo]]
      path = "~/repos/api"
      aliases = ["the api", "api server"]
      linear_teams = ["ENG"]

      [[repo]]
      path = "repos/web"

      [ui]
      theme = "light"

      [keys]
      leader = "ctrl+b"
      [keys.bindings]
      "tab.next" = ["<leader> n", "alt+n"]
      "list.down" = []

      [modules]
      disabled = ["plain"]

      [configured]
      mode = "careful"
      retries = 3

      [voice]
      input_device = "AirPods"
      """)
    #expect(result.errors.isEmpty, "\(messages(result))")
    let config = result.config
    #expect(config.repos.map(\.name) == ["api", "web"])
    #expect(config.repos.first?.aliases == ["the api", "api server"])
    #expect(config.repos.last?.url == directory.appending(path: "repos/web").standardizedFileURL)
    #expect(config.theme == .light)
    #expect(config.keys.leader == KeyChord("ctrl+b"))
    #expect(config.keys.bindings["tab.next"]?.count == 2)
    #expect(config.keys.bindings["list.down"] == [])
    #expect(config.disabledModules == ["plain"])
    #expect(
      config.sections["configured"] as? SettingsModule.Settings
        == SettingsModule.Settings(mode: .careful, retries: 3))
  }

  @Test func environmentCarriesConfigIntoModules() {
    let result = parse(
      """
      [[repo]]
      path = "repos/api"
      [modules]
      disabled = ["plain"]
      [configured]
      mode = "fast"
      """)
    let environment = result.config.environment(for: modules, secrets: InMemorySecretStore())
    let loaded = ModuleLoader.load(modules, environment: environment)
    #expect(loaded.moduleIDs == ["configured"])
    #expect((loaded.modules.first as? SettingsModule)?.settings?.mode == .fast)
    #expect(environment.repos.map(\.name) == ["api"])
    #expect(result.config.enabled(modules).map { $0.id } == ["configured"])
  }

  @Test func missingFileGivesDefaultsUnlessRequired() {
    let missing = directory.appending(path: "nope.toml")
    let optional = ConfigLoader.load(from: missing, modules: modules, home: directory)
    #expect(!optional.exists)
    #expect(optional.errors.isEmpty)
    #expect(optional.config.repos.isEmpty)
    #expect(optional.displayPath == "~/nope.toml")
    let required = ConfigLoader.load(
      from: missing, modules: modules, required: true, home: directory)
    #expect(required.errors.map(\.message) == ["no such file"])
  }

  @Test func locationPrefersFlagThenEnvironmentThenDefault() {
    let home = URL(filePath: "/Users/someone")
    #expect(
      ConfigLoader.location(explicit: "~/a.toml", environment: ["VOCODER_CONFIG": "/b"], home: home)
        .path == "/Users/someone/a.toml")
    #expect(
      ConfigLoader.location(explicit: nil, environment: ["VOCODER_CONFIG": "/b.toml"], home: home)
        .path == "/b.toml")
    #expect(
      ConfigLoader.location(explicit: nil, environment: [:], home: home).path
        == "/Users/someone/.config/vocoder/config.toml")
  }

  @Test func syntaxErrorsHaveALine() {
    let result = parse(
      """
      [ui]
      theme = "dark

      """)
    #expect(result.errors.count == 1)
    let error = result.errors.first
    #expect(error?.line == 2)
    #expect(error?.message.hasPrefix("invalid TOML") == true)
    #expect(error?.description.hasPrefix("~/config.toml:2: invalid TOML") == true)
  }

  @Test func allErrorsAreCollectedWithLinesAndHints() {
    let result = parse(
      """
      [[repo]]
      path = "repos/missing"

      [[repo]]
      path = "repos/file.txt"

      [[repo]]
      path = "repos/api"
      aliases = ["api"]

      [[repo]]
      path = "repos/web"
      aliases = ["API", ""]
      alias = ["typo"]

      [ui]
      theme = "solarized"
      font = "x"

      [keys]
      leader = "hyper"
      [keys.bindings]
      "tab.next" = ["ctrl+tab+x"]

      [modules]
      disabled = ["plian"]

      [configured]
      mode = "reckless"

      [plain]
      x = 1

      [moduels]
      """)
    let byPath = Dictionary(grouping: result.errors, by: { $0.keyPath ?? "" })
    #expect(byPath["repo[1].path"]?.first?.message.hasPrefix("no such directory") == true)
    #expect(byPath["repo[1].path"]?.first?.line == 2)
    #expect(byPath["repo[2].path"]?.first?.message.hasPrefix("not a directory") == true)
    #expect(byPath["repo[2].path"]?.first?.line == 5)
    #expect(byPath["repo[4].aliases[1]"]?.first?.message == "alias 'API' is also used by repo[3]")
    #expect(byPath["repo[4].aliases[2]"]?.first?.message == "alias is empty")
    #expect(byPath["repo[4].alias"]?.first?.hint == "did you mean 'aliases'?")
    #expect(byPath["repo[4].alias"]?.first?.line == 14)
    #expect(byPath["ui.theme"]?.first?.hint == "one of: auto, dark, light")
    #expect(byPath["ui.theme"]?.first?.line == 17)
    #expect(byPath["ui.font"]?.first?.message == "unknown key")
    #expect(byPath["keys.leader"]?.first?.line == 21)
    #expect(byPath["keys.bindings.\"tab.next\""]?.first?.line == 23)
    #expect(byPath["modules.disabled[1]"]?.first?.hint == "did you mean 'plain'?")
    #expect(byPath["configured.mode"] != nil)
    #expect(byPath["configured.mode"]?.first?.line == 29)
    #expect(byPath["plain"]?.first?.message == "the plain module has no settings")
    #expect(byPath["moduels"]?.first?.hint == "did you mean [modules]?")
    #expect(byPath["moduels"]?.first?.line == 34)
    #expect(result.errors.count == 13, "\(messages(result))")
    // The valid parts still load.
    #expect(result.config.repos.map(\.name) == ["api", "web"])
  }

  @Test func typeErrorsNameTheExpectedType() {
    let result = parse(
      """
      [ui]
      theme = 3

      [modules]
      disabled = "plain"

      [configured]
      retries = 2
      """)
    let byPath = Dictionary(grouping: result.errors, by: { $0.keyPath ?? "" })
    #expect(byPath["ui.theme"]?.first?.message == "expected a string")
    #expect(byPath["modules.disabled"]?.first?.message == "expected a list")
    #expect(byPath["configured.mode"]?.first?.message == "missing required key 'mode'")
    #expect(result.errors.count == 3, "\(messages(result))")
  }

  @Test func unknownSectionListsTheKnownOnes() {
    let result = parse("[zzz]\n")
    #expect(result.errors.first?.hint?.contains("modules: configured, plain") == true)
  }

  @Test func repoNeedsAPath() {
    let result = parse("[[repo]]\naliases = [\"x\"]\n")
    #expect(result.errors.first?.keyPath == "repo[1].path")
    #expect(result.errors.first?.message == "missing required key 'path'")
  }

  @Test func duplicateRepoPaths() {
    let result = parse("[[repo]]\npath = \"repos/api\"\n[[repo]]\npath = \"~/repos/api/\"\n")
    #expect(result.errors.map(\.message) == ["~/repos/api is already repo[1]"])
  }

  @Test func suggestions() {
    #expect(Suggestion.distance("kitten", "sitting") == 3)
    #expect(Suggestion.distance("", "abc") == 3)
    #expect(Suggestion.closest(to: "thme", in: ["theme", "keys"]) == "theme")
    #expect(Suggestion.closest(to: "zz", in: ["theme"]) == nil)
  }
}
