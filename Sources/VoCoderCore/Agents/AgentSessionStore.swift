import Foundation
import Synchronization

/// Remembers each repo's last agent session per backend so a repo tab can resume it
/// (`~/Library/Application Support/VoCoder/agent-sessions.json`). Failures to read or write
/// are logged and treated as "nothing remembered": losing this only means starting fresh.
public final class AgentSessionStore: Sendable {
  public struct Record: Codable, Sendable, Equatable {
    public var repo: String
    public var backend: String
    public var session: AgentSessionID
    public var updated: Date
  }

  public static var defaultFile: URL {
    URL.applicationSupportDirectory.appending(path: "VoCoder/agent-sessions.json")
  }

  public let file: URL
  private let records: Mutex<[Record]?>
  private let log = Log(category: "agent.sessions")

  public init(file: URL = AgentSessionStore.defaultFile) {
    self.file = file
    records = Mutex(nil)
  }

  public func lastSession(repo: URL, backend: ProviderID) -> AgentSessionID? {
    records.withLock { records in
      load(&records).first { $0.repo == Self.key(repo) && $0.backend == backend.rawValue }?
        .session
    }
  }

  public func record(_ session: AgentSessionID, repo: URL, backend: ProviderID) {
    update { records in
      records.removeAll { $0.repo == Self.key(repo) && $0.backend == backend.rawValue }
      records.append(
        Record(repo: Self.key(repo), backend: backend.rawValue, session: session, updated: .now))
    }
  }

  public func forget(repo: URL, backend: ProviderID) {
    update { records in
      records.removeAll { $0.repo == Self.key(repo) && $0.backend == backend.rawValue }
    }
  }

  private func update(_ change: (inout [Record]) -> Void) {
    records.withLock { records in
      var current = load(&records)
      change(&current)
      records = current
      save(current)
    }
  }

  private func load(_ cache: inout [Record]?) -> [Record] {
    if let cache { return cache }
    var loaded: [Record] = []
    if let data = try? Data(contentsOf: file) {
      do {
        loaded = try Self.decoder.decode([Record].self, from: data)
      } catch {
        log.error("ignoring unreadable \(file.path): \(error)")
      }
    }
    cache = loaded
    return loaded
  }

  private func save(_ records: [Record]) {
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Self.encoder.encode(records).write(to: file, options: .atomic)
    } catch {
      log.error("couldn't save \(file.path): \(error)")
    }
  }

  private static func key(_ repo: URL) -> String { repo.standardizedFileURL.path }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

public enum AgentSessionStoreKey: ServiceKey {
  public static var defaultValue: AgentSessionStore? { nil }
}

extension ServiceContainer {
  /// Where repo tabs remember agent sessions; nil (tests, unless they set one) remembers
  /// nothing. The app sets the real store.
  public var agentSessions: AgentSessionStore? {
    get { self[AgentSessionStoreKey.self] }
    set { self[AgentSessionStoreKey.self] = newValue }
  }
}
