import Foundation
import Observation

/// The app's state: tabs and selection, attention items, loaded modules and their issues.
/// `@Observable` is the change stream: the UI host re-renders when anything it read changes.
@MainActor
@Observable
public final class AppState {
  /// In tab-bar order.
  public private(set) var tabs: [any Tab] = []
  public private(set) var selectedTabID: TabID?
  /// Pending items, oldest first. Ordering and delivery policy arrive with the queue (P3-01).
  public private(set) var attention: [AttentionItem] = []
  public internal(set) var modules: [ModuleID] = []
  /// What the voice bar shows. Static (`.off`) until the voice layer drives it (Phase 2).
  public var voice = VoiceStatus()
  public private(set) var issues: [ModuleIssue] = []

  @ObservationIgnored private let log = Log(category: "state")

  public init() {}

  public var selectedTab: (any Tab)? { selectedTabID.flatMap(tab) }

  public func tab(_ id: TabID) -> (any Tab)? { tabs.first { $0.id == id } }

  // MARK: Tabs

  /// Adds `tab` at `index` (default: the end) and selects it if nothing is selected. Returns
  /// false if a tab with its id is already open.
  @discardableResult
  public func open(_ tab: any Tab, at index: Int? = nil) -> Bool {
    guard self.tab(tab.id) == nil else {
      log.error("tab \(tab.id) is already open")
      return false
    }
    tabs.insert(tab, at: min(index ?? tabs.count, tabs.count))
    if selectedTabID == nil { select(tab.id) }
    return true
  }

  /// Shows tab `id`. Returns false if there is no such tab.
  @discardableResult
  public func select(_ id: TabID) -> Bool {
    guard let next = tab(id) else { return false }
    guard id != selectedTabID else { return true }
    selectedTab?.didDeactivate()
    selectedTabID = id
    next.didActivate()
    return true
  }

  /// Removes tab `id`; if it was selected, the next tab (or else the previous) is selected.
  @discardableResult
  public func close(_ id: TabID) -> Bool {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
    let closing = tabs[index]
    if id == selectedTabID {
      closing.didDeactivate()
      selectedTabID = nil
    }
    closing.willClose()
    tabs.remove(at: index)
    if selectedTabID == nil, !tabs.isEmpty {
      select(tabs[min(index, tabs.count - 1)].id)
    }
    return true
  }

  /// Moves tab `id` to `index` (clamped). Returns false if there is no such tab.
  @discardableResult
  public func move(_ id: TabID, to index: Int) -> Bool {
    guard let from = tabs.firstIndex(where: { $0.id == id }) else { return false }
    let tab = tabs.remove(at: from)
    tabs.insert(tab, at: max(0, min(index, tabs.count)))
    return true
  }

  /// The tab whose title or an alias is `name`, ignoring case, spaces at the ends and a leading
  /// "the" ("go to the api" → alias "api"); nil if none or several match.
  public func tab(matching name: String) -> (any Tab)? {
    func normalised(_ text: String) -> String {
      var text = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
      if text.hasPrefix("the ") { text = String(text.dropFirst(4)) }
      return text
    }
    let wanted = normalised(name)
    guard !wanted.isEmpty else { return nil }
    let matches = tabs.filter { tab in
      ([tab.title] + tab.aliases).contains { normalised($0) == wanted }
    }
    return matches.count == 1 ? matches[0] : nil
  }

  /// Closes every tab (app shutdown).
  public func closeAll() {
    while let last = tabs.last { close(last.id) }
  }

  // MARK: Attention

  /// Adds `item`, or replaces the item with the same id. Expired items are dropped.
  public func post(_ item: AttentionItem, now: Date = Date()) {
    let index = attention.firstIndex { $0.id == item.id }
    if item.isExpired(at: now) {
      if let index { attention.remove(at: index) }
    } else if let index {
      attention[index] = item
    } else {
      attention.append(item)
    }
  }

  public func dismissAttention(_ id: AttentionItemID) {
    attention.removeAll { $0.id == id }
  }

  public func removeExpiredAttention(now: Date = Date()) {
    attention.removeAll { $0.isExpired(at: now) }
  }

  // MARK: Modules

  public func report(_ issue: ModuleIssue) {
    log.error("module issue: \(issue)")
    issues.append(issue)
  }

  func report(_ newIssues: [ModuleIssue]) { issues += newIssues }
}
