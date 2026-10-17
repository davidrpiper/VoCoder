import Foundation

/// `vocoder auth <module>`: asks for each secret a module declares and stores it. Logs which
/// secrets changed, never their values.
public enum SecretSetup {
  public enum Outcome: Sendable, Equatable {
    case stored
    /// Nothing entered; the old value (if any) stays.
    case unchanged
    case removed
  }

  /// Asks `read` for each of `specs` (nil or blank keeps the current value) and stores the
  /// answers in `store`.
  public static func store(
    _ specs: [SecretSpec], module: ModuleID, in store: any SecretStore,
    log: Log = Log(category: "secrets"), read: (SecretSpec) throws -> String?
  ) throws -> [(spec: SecretSpec, outcome: Outcome)] {
    var outcomes: [(SecretSpec, Outcome)] = []
    for spec in specs {
      let key = SecretKey(module: module, name: spec.name)
      let value = try read(spec)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if value.isEmpty {
        outcomes.append((spec, .unchanged))
        continue
      }
      try store.setSecret(value, for: key)
      log.info("secret stored for \(key)")
      outcomes.append((spec, .stored))
    }
    return outcomes
  }

  /// Removes all of `specs` from `store`.
  public static func remove(
    _ specs: [SecretSpec], module: ModuleID, from store: any SecretStore,
    log: Log = Log(category: "secrets")
  ) throws -> [(spec: SecretSpec, outcome: Outcome)] {
    try specs.map { spec in
      let key = SecretKey(module: module, name: spec.name)
      try store.removeSecret(for: key)
      log.info("secret removed for \(key)")
      return (spec, .removed)
    }
  }

  /// The names of `specs` that aren't set.
  public static func missing(
    _ specs: [SecretSpec], module: ModuleID, in store: any SecretStore
  ) throws -> [SecretSpec] {
    try specs.filter { try !store.hasSecret(for: SecretKey(module: module, name: $0.name)) }
  }
}
