import Foundation

/// How urgently an item wants the user (DESIGN §4.7).
public enum AttentionPriority: Int, Sendable, Comparable, CaseIterable {
  /// Doc edits, status changes: batched into digests.
  case ambient
  /// Agent turn finished, issue assigned.
  case soon
  /// Agent needs approval, meeting in ≤2 min.
  case interrupt

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Something that may deserve the user's attention. Posting an item with an existing id
/// replaces it (sources update items in place). Actions arrive with the queue (P3-01).
public struct AttentionItem: Identifiable, Sendable, Equatable {
  public let id: AttentionItemID
  /// The attention source that posted it.
  public let source: ProviderID
  public var priority: AttentionPriority
  public var title: String
  /// What VoCoder says when it delivers the item.
  public var spoken: String
  /// After this the item is dropped unseen.
  public var expiry: Date?

  public init(
    id: AttentionItemID, source: ProviderID, priority: AttentionPriority, title: String,
    spoken: String? = nil, expiry: Date? = nil
  ) {
    self.id = id
    self.source = source
    self.priority = priority
    self.title = title
    self.spoken = spoken ?? title
    self.expiry = expiry
  }

  public func isExpired(at date: Date) -> Bool { expiry.map { $0 <= date } ?? false }
}

/// Emits attention items (agent, calendar, tracker and docs modules). The app reads `items`
/// once, from start until the stream finishes or the app stops.
public protocol AttentionSource: Provider {
  var items: AsyncStream<AttentionItem> { get }
}
