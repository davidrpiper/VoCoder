/// Core's checks: the config file, module problems, the keymap and module secrets. Each takes
/// what it inspects as values so tests can feed it directly.
public enum CoreDoctorChecks {
  public static func config(_ result: ConfigLoadResult) -> any DoctorCheck {
    ClosureDoctorCheck(id: "core.config", title: "Config") {
      guard result.exists else {
        return .warning(
          "no config file at \(result.displayPath) (running on defaults)",
          hint: "create one with `vocoder config init`")
      }
      guard result.isValid else {
        let count = result.errors.count
        return .failure(
          "\(count) error\(count == 1 ? "" : "s") in \(result.displayPath)\n"
            + result.errors.map(\.description).joined(separator: "\n"),
          hint: "fix them, then `vocoder config check`")
      }
      let repos = result.config.repos.count
      return .ok("\(result.displayPath) (\(repos) repo\(repos == 1 ? "" : "s"))")
    }
  }

  public static func modules(loaded: [ModuleID], issues: [ModuleIssue]) -> any DoctorCheck {
    ClosureDoctorCheck(id: "core.modules", title: "Modules") {
      let names = loaded.map(\.rawValue).joined(separator: ", ")
      guard issues.isEmpty else {
        return .failure(
          "\(issues.count) problem\(issues.count == 1 ? "" : "s")\n"
            + issues.map(\.description).joined(separator: "\n"),
          hint: "see `make logs`; disable a broken module with [modules] disabled")
      }
      return .ok(loaded.isEmpty ? "none enabled" : names)
    }
  }

  /// `Keymap.issues`: unknown command ids in `[keys.bindings]`, shadowed sequences.
  public static func keymap(issues: [String]) -> any DoctorCheck {
    ClosureDoctorCheck(id: "core.keymap", title: "Key bindings") {
      guard issues.isEmpty else {
        return .warning(
          issues.joined(separator: "\n"),
          hint: "check [keys.bindings] against the command ids in help (`?`)")
      }
      return .ok("no conflicts")
    }
  }

  /// Every enabled module's declared secrets are set.
  public static func secrets(
    modules: [(id: ModuleID, specs: [SecretSpec])], store: any SecretStore
  ) -> any DoctorCheck {
    ClosureDoctorCheck(id: "core.secrets", title: "Secrets") {
      var missing: [String] = []
      var commands: [String] = []
      var set = 0
      for (id, specs) in modules where !specs.isEmpty {
        do {
          let absent = try SecretSetup.missing(specs, module: id, in: store)
          set += specs.count - absent.count
          if !absent.isEmpty {
            missing.append("\(id): " + absent.map(\.title).joined(separator: ", ") + " not set")
            commands.append("`vocoder auth \(id)`")
          }
        } catch {
          return .failure("\(error)", hint: "unlock the login keychain and try again")
        }
      }
      guard missing.isEmpty else {
        return .warning(
          missing.joined(separator: "\n"),
          hint: "run \(commands.joined(separator: ", ")), or disable the module in [modules]")
      }
      return set == 0 ? .ok("no enabled module needs one") : .ok("\(set) set")
    }
  }
}
