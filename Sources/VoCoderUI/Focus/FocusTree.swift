/// The focusable views and scopes of one render, in render order (pre-order).
struct FocusTree {
  struct Entry {
    let id: FocusID
    let isScope: Bool
    /// Scope only: focus can't leave it while it's in the tree (modals).
    let trap: Bool
    /// Leaf only: the bridge widget that receives typed keys while focused.
    let widgetId: String?
    let handler: ActionHandler?
    let parent: Int?
  }

  private(set) var entries: [Entry] = []
  private var indexByID: [FocusID: Int] = [:]

  var isEmpty: Bool { entries.isEmpty }

  func entry(_ id: FocusID) -> Entry? { indexByID[id].map { entries[$0] } }

  /// The scopes containing `id`, outermost first, then `id` itself.
  func path(to id: FocusID) -> [FocusID] {
    guard var index = indexByID[id] else { return [] }
    var path = [entries[index].id]
    while let parent = entries[index].parent {
      path.append(entries[parent].id)
      index = parent
    }
    return path.reversed()
  }

  /// Leaves inside `scope` (all leaves for nil), in render order.
  func leaves(in scope: FocusID?) -> [FocusID] {
    guard let scope else { return entries.filter { !$0.isScope }.map(\.id) }
    guard let scopeIndex = indexByID[scope] else { return [] }
    return entries.indices.filter { !entries[$0].isScope && isDescendant($0, of: scopeIndex) }
      .map { entries[$0].id }
  }

  /// The trap scope focus is confined to: the last one rendered (the topmost modal).
  var activeTrap: FocusID? { entries.last { $0.isScope && $0.trap }?.id }

  private func isDescendant(_ index: Int, of ancestor: Int) -> Bool {
    var current = entries[index].parent
    while let parent = current {
      if parent == ancestor { return true }
      current = entries[parent].parent
    }
    return false
  }

  /// Collects entries during a render.
  struct Builder {
    private(set) var tree = FocusTree()
    private var scopeStack: [Int] = []
    private(set) var duplicates: [FocusID] = []

    mutating func addLeaf(_ id: FocusID, widgetId: String?, handler: ActionHandler?) {
      add(
        Entry(
          id: id, isScope: false, trap: false, widgetId: widgetId, handler: handler,
          parent: scopeStack.last))
    }

    mutating func beginScope(_ id: FocusID, trap: Bool, handler: ActionHandler?) {
      let added = add(
        Entry(
          id: id, isScope: true, trap: trap, widgetId: nil, handler: handler,
          parent: scopeStack.last))
      // A duplicate scope still nests its children, under the first one with that id.
      scopeStack.append(added ?? tree.indexByID[id]!)
    }

    mutating func endScope() { scopeStack.removeLast() }

    @discardableResult
    private mutating func add(_ entry: Entry) -> Int? {
      guard tree.indexByID[entry.id] == nil else {
        duplicates.append(entry.id)
        return nil
      }
      tree.indexByID[entry.id] = tree.entries.count
      tree.entries.append(entry)
      return tree.entries.count - 1
    }
  }
}
