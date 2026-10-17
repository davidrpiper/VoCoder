import Foundation

/// Reads and validates the config file. Every problem is collected (not just the first) so one
/// `vocoder config check` shows them all; the app refuses to start while there are any.
@MainActor
public enum ConfigLoader {
  /// Sections owned by Core. `voice`, `tasks` and `docs` are reserved for their work packages
  /// (P2, P4, P5) and not read yet.
  public static let coreSections = ["repo", "keys", "ui", "modules", "voice", "tasks", "docs"]

  /// `--config`, then `$VOCODER_CONFIG`, then `~/.config/vocoder/config.toml`.
  public nonisolated static func location(
    explicit: String?, environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL {
    if let path = explicit ?? environment["VOCODER_CONFIG"], !path.isEmpty {
      return resolve(path, relativeTo: URL.currentDirectory(), home: home)
    }
    return home.appending(path: ".config/vocoder/config.toml")
  }

  /// Loads `url`. A missing file gives the defaults, or an error when `required` (an explicit
  /// `--config`). `modules` are the compiled-in module types: their ids are the known module
  /// sections, and their section types decode them.
  public static func load(
    from url: URL, modules: [any VoCoderModule.Type], required: Bool = false,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> ConfigLoadResult {
    let display = displayPath(url, home: home)
    guard FileManager.default.fileExists(atPath: url.path) else {
      let errors =
        required
        ? [
          ConfigError(
            file: display, message: "no such file",
            hint: "create it with `vocoder config init --config \(display)`")
        ] : []
      return ConfigLoadResult(
        config: AppConfig(), errors: errors, exists: false, displayPath: display)
    }
    do {
      let text = try String(contentsOf: url, encoding: .utf8)
      return parse(text, file: url, modules: modules, home: home)
    } catch {
      return ConfigLoadResult(
        config: AppConfig(),
        errors: [ConfigError(file: display, message: "can't be read as UTF-8 text: \(error)")],
        exists: true, displayPath: display)
    }
  }

  /// Parses and validates config text. Repo paths are checked on disk, relative to `file`'s
  /// directory.
  public static func parse(
    _ text: String, file: URL, modules: [any VoCoderModule.Type],
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> ConfigLoadResult {
    var parser = Parser(
      text: text, file: file, display: displayPath(file, home: home), modules: modules, home: home)
    parser.run()
    // In file order (stable within a line).
    let errors = parser.errors.enumerated()
      .sorted { ($0.element.line ?? 0, $0.offset) < ($1.element.line ?? 0, $1.offset) }
      .map(\.element)
    return ConfigLoadResult(
      config: parser.config, errors: errors, exists: true, displayPath: parser.display)
  }

  /// `~/…` for paths under `home`.
  public nonisolated static func displayPath(_ url: URL, home: URL) -> String {
    let path = url.standardizedFileURL.path
    let homePath = home.standardizedFileURL.path
    if path == homePath { return "~" }
    if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
    return path
  }

  /// Expands `~`; relative paths are relative to `base`.
  nonisolated static func resolve(_ path: String, relativeTo base: URL, home: URL) -> URL {
    if path == "~" { return home }
    if path.hasPrefix("~/") {
      return home.appending(path: String(path.dropFirst(2))).standardizedFileURL
    }
    if path.hasPrefix("/") { return URL(filePath: path).standardizedFileURL }
    return base.appending(path: path).standardizedFileURL
  }
}

// MARK: - Raw shapes of the core sections

private struct RawRepo: Decodable {
  var path: String
  var aliases: [String]?
}

private struct RawKeys: Decodable {
  var leader: String?
  var bindings: [String: [String]]?
}

private struct RawUI: Decodable {
  var theme: String?
}

private struct RawModules: Decodable {
  var disabled: [String]?
}

/// Decodes one element of an array on its own, so one bad `[[repo]]` doesn't hide the others.
private struct Lenient<Value: Decodable>: Decodable {
  let result: Result<Value, any Error>

  init(from decoder: any Decoder) throws {
    result = Result { try Value(from: decoder) }
  }
}

// MARK: - Parser

@MainActor
private struct Parser {
  let text: String
  let file: URL
  let display: String
  let modules: [any VoCoderModule.Type]
  let home: URL
  let locator: ConfigLineLocator
  var config = AppConfig()
  var errors: [ConfigError] = []
  private var document: TOMLDocument?

  init(
    text: String, file: URL, display: String, modules: [any VoCoderModule.Type], home: URL
  ) {
    self.text = text
    self.file = file
    self.display = display
    self.modules = modules
    self.home = home
    locator = ConfigLineLocator(text: text)
    config.file = file
  }

  var moduleIDs: [String] { modules.map { $0.id.rawValue } }

  mutating func run() {
    do {
      document = try TOMLDocument(text: text)
    } catch {
      errors.append(
        ConfigError(
          file: display, line: error.line, message: "invalid TOML: \(error.message)",
          hint: "see https://toml.io for the syntax"))
      return
    }
    checkTopLevel()
    readRepos()
    readKeys()
    readUI()
    readModules()
    readModuleSections()
  }

  // MARK: Helpers

  mutating func report(
    _ path: ConfigPath?, _ message: String, hint: String? = nil
  ) {
    errors.append(
      ConfigError(
        file: display, line: path.flatMap { locator.line(of: $0) }, keyPath: path?.description,
        message: message, hint: hint))
  }

  mutating func report(decoding error: any Error, at fallback: ConfigPath) {
    guard let error = error as? DecodingError else {
      reportTOMLError("\(error)", at: fallback)
      return
    }
    switch error {
    case .typeMismatch(let type, let context), .valueNotFound(let type, let context):
      report(path(context, fallback), "expected \(Self.describe(type))")
    case .keyNotFound(let key, let context):
      report(
        path(context, fallback).appending(.key(key.stringValue)),
        "missing required key '\(key.stringValue)'", hint: "add `\(key.stringValue) = …`")
    case .dataCorrupted(let context):
      report(path(context, fallback), context.debugDescription)
    @unknown default:
      report(fallback, "\(error)")
    }
  }

  /// TOMLDecoder reports some type mismatches with its own error type:
  /// `(Line 2) Type mismatch at table key 'theme': expected string.`
  private mutating func reportTOMLError(_ description: String, at fallback: ConfigPath) {
    let parsed = TOMLDocument.syntaxError(from: description)
    if let match = parsed.message.firstMatch(of: /key '(.+)': expected (\w+)/) {
      let path = fallback.appending(.key(String(match.1)))
      let expected = String(match.2)
      let article = "aeiou".contains(expected.first ?? "x") ? "an" : "a"
      errors.append(
        ConfigError(
          file: display, line: parsed.line ?? locator.line(of: path), keyPath: path.description,
          message: "expected \(article) \(expected)"))
    } else {
      errors.append(
        ConfigError(
          file: display, line: parsed.line ?? locator.line(of: fallback),
          keyPath: fallback.description, message: parsed.message))
    }
  }

  private func path(_ context: DecodingError.Context, _ fallback: ConfigPath) -> ConfigPath {
    context.codingPath.isEmpty ? fallback : ConfigPath(codingPath: context.codingPath)
  }

  static func describe(_ type: Any.Type) -> String {
    switch type {
    case is String.Type: return "a string"
    case is Bool.Type: return "true or false"
    case is any BinaryInteger.Type: return "a whole number"
    case is any BinaryFloatingPoint.Type: return "a number"
    default:
      let name = String(describing: type)
      if name.contains("Array") || name.contains("Unkeyed") { return "a list" }
      return "a table"
    }
  }

  func decode<Value: Decodable>(_ type: Value.Type, at key: String) throws -> Value? {
    try document?.decode(type, at: key)
  }

  mutating func checkKeys(
    _ keys: [String]?, at path: ConfigPath, allowed: [String]
  ) {
    for key in keys ?? [] where !allowed.contains(key) {
      let suggestion = Suggestion.closest(to: key, in: allowed)
      report(
        path.appending(.key(key)), "unknown key",
        hint: suggestion.map { "did you mean '\($0)'?" }
          ?? "allowed here: \(allowed.joined(separator: ", "))")
    }
  }

  // MARK: Sections

  mutating func checkTopLevel() {
    let known = ConfigLoader.coreSections + moduleIDs
    for key in document?.topLevelKeys ?? [] where !known.contains(key) {
      let hint =
        Suggestion.closest(to: key, in: known).map { "did you mean [\($0)]?" }
        ?? "known sections: \(ConfigLoader.coreSections.joined(separator: ", ")); modules: "
        + moduleIDs.joined(separator: ", ")
      report(ConfigPath(key), "unknown section", hint: hint)
    }
  }

  mutating func readRepos() {
    let entries: [Lenient<RawRepo>]
    do {
      guard let decoded = try decode([Lenient<RawRepo>].self, at: "repo") else { return }
      entries = decoded
    } catch {
      report(decoding: error, at: ConfigPath("repo"))
      return
    }
    let tableKeys = document?.keys(ofTablesIn: "repo") ?? []
    var names: [String: Int] = [:]  // lower-cased alias → repo number
    var paths: [URL: Int] = [:]
    let base = file.deletingLastPathComponent()
    for (offset, entry) in entries.enumerated() {
      let number = offset + 1
      let at = ConfigPath([.key("repo"), .index(number)])
      if offset < tableKeys.count {
        // Extra keys are allowed (modules read them later, e.g. `linear_teams` in P4-04), but
        // misspelling the two Core keys is caught.
        for key in tableKeys[offset] where !["path", "aliases"].contains(key) {
          if let near = Suggestion.closest(to: key, in: ["path", "aliases"]) {
            report(at.appending(.key(key)), "unknown key", hint: "did you mean '\(near)'?")
          }
        }
      }
      let raw: RawRepo
      switch entry.result {
      case .success(let value): raw = value
      case .failure(let error):
        report(decoding: error, at: at)
        continue
      }
      let pathAt = at.appending(.key("path"))
      guard !raw.path.trimmingCharacters(in: .whitespaces).isEmpty else {
        report(pathAt, "is empty", hint: "the repository's directory, e.g. \"~/projects/app\"")
        continue
      }
      let url = ConfigLoader.resolve(raw.path, relativeTo: base, home: home)
      var isDirectory: ObjCBool = false
      let shown = ConfigLoader.displayPath(url, home: home)
      if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
        report(pathAt, "no such directory: \(shown)", hint: "fix the path or remove this [[repo]]")
        continue
      }
      if !isDirectory.boolValue {
        report(pathAt, "not a directory: \(shown)", hint: "point it at the repository's root")
        continue
      }
      if let other = paths[url] {
        report(pathAt, "\(shown) is already repo[\(other)]", hint: "remove one of them")
        continue
      }
      paths[url] = number

      var aliases: [String] = []
      for (index, alias) in (raw.aliases ?? []).enumerated() {
        let aliasAt = at.appending(.key("aliases")).appending(.index(index + 1))
        let trimmed = alias.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
          report(aliasAt, "alias is empty")
          continue
        }
        if let other = names[trimmed.lowercased()], other != number {
          report(
            aliasAt, "alias '\(trimmed)' is also used by repo[\(other)]",
            hint: "aliases pick a repo by voice and in the palette, so they must be unique")
          continue
        }
        names[trimmed.lowercased()] = number
        aliases.append(trimmed)
      }
      config.repos.append(RepoRoot(url: url, aliases: aliases))
    }
  }

  mutating func readKeys() {
    let keys: RawKeys
    do {
      guard let decoded = try decode(RawKeys.self, at: "keys") else { return }
      keys = decoded
    } catch {
      report(decoding: error, at: ConfigPath("keys"))
      return
    }
    checkKeys(
      document?.keys(ofTable: ["keys"]), at: ConfigPath("keys"), allowed: ["leader", "bindings"])
    let (overrides, problems) = KeyBindingOverrides.parse(
      leader: keys.leader, bindings: keys.bindings ?? [:])
    for problem in problems {
      let path =
        problem.command.map { ConfigPath("keys", "bindings", $0) } ?? ConfigPath("keys", "leader")
      report(
        path, problem.message,
        hint: "keys are written like \"ctrl+p\", \"alt+1\", \"<leader> t n\"; [] unbinds")
    }
    config.keys = overrides
  }

  mutating func readUI() {
    let ui: RawUI
    do {
      guard let decoded = try decode(RawUI.self, at: "ui") else { return }
      ui = decoded
    } catch {
      report(decoding: error, at: ConfigPath("ui"))
      return
    }
    checkKeys(document?.keys(ofTable: ["ui"]), at: ConfigPath("ui"), allowed: ["theme"])
    guard let theme = ui.theme else { return }
    if let preference = ThemePreference(rawValue: theme) {
      config.theme = preference
    } else {
      report(
        ConfigPath("ui", "theme"), "unknown theme '\(theme)'",
        hint: "one of: " + ThemePreference.allCases.map(\.rawValue).joined(separator: ", "))
    }
  }

  mutating func readModules() {
    let section: RawModules
    do {
      guard let decoded = try decode(RawModules.self, at: "modules") else { return }
      section = decoded
    } catch {
      report(decoding: error, at: ConfigPath("modules"))
      return
    }
    checkKeys(
      document?.keys(ofTable: ["modules"]), at: ConfigPath("modules"), allowed: ["disabled"])
    for (index, id) in (section.disabled ?? []).enumerated() {
      if moduleIDs.contains(id) {
        config.disabledModules.insert(ModuleID(id))
      } else {
        let near = Suggestion.closest(to: id, in: moduleIDs)
        report(
          ConfigPath([.key("modules"), .key("disabled"), .index(index + 1)]),
          "unknown module '\(id)'",
          hint: near.map { "did you mean '\($0)'?" }
            ?? "modules: \(moduleIDs.joined(separator: ", "))")
      }
    }
  }

  mutating func readModuleSections() {
    for module in modules {
      let id = module.id.rawValue
      guard document?.contains(id) == true else { continue }
      guard let type = module.configSection else {
        report(
          ConfigPath(id), "the \(id) module has no settings",
          hint: "remove the [\(id)] section")
        continue
      }
      do {
        if let section = try decodeSection(type, at: id) {
          config.sections[module.id] = section
        }
      } catch {
        report(decoding: error, at: ConfigPath(id))
      }
      if let allowed = type.keys {
        checkKeys(document?.keys(ofTable: [id]), at: ConfigPath(id), allowed: allowed)
      }
    }
  }

  private func decodeSection<Section: ConfigSection>(_ type: Section.Type, at key: String) throws
    -> (any ConfigSection)?
  {
    try decode(type, at: key)
  }
}
