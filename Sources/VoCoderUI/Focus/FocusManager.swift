import Observation

/// Owns keyboard focus (which is also the voice cursor, DESIGN §2.2). Each render hands it the
/// new focus tree; it keeps focus on the same leaf when possible, otherwise moves it to the
/// nearest survivor. Focus is confined to the topmost trap scope (modal) while one is shown.
@MainActor
@Observable
public final class FocusManager {
  /// The focused leaf.
  public private(set) var focused: FocusID?

  @ObservationIgnored private(set) var tree = FocusTree()
  /// Requested with `focus(_:)` before it was rendered; applied when it appears.
  @ObservationIgnored private var pending: FocusID?
  /// Scope → its most recently focused leaf (so focusing a pane returns to where you were).
  @ObservationIgnored private var remembered: [FocusID: FocusID] = [:]
  /// Trap scope → the leaf focused before it appeared, restored when it goes away.
  @ObservationIgnored private var trapReturn: [FocusID: FocusID] = [:]
  @ObservationIgnored private var lastPath: [FocusID] = []
  @ObservationIgnored private var lastTrap: FocusID?
  /// Called whenever `focused` changes (the host syncs the bridge's focused widget at once, so
  /// keys typed right after a focus move reach the right widget).
  @ObservationIgnored var onChange: (@MainActor () -> Void)?

  public init() {}

  /// Scopes containing the focused leaf, outermost first, then the leaf.
  public var path: [FocusID] { focused.map { tree.path(to: $0) } ?? [] }

  /// The bridge widget that should receive typed keys.
  public var focusedWidget: String? { focused.flatMap { tree.entry($0)?.widgetId } }

  /// Action handlers along the focus path, innermost first.
  var handlerChain: [ActionHandler] { path.reversed().compactMap { tree.entry($0)?.handler } }

  /// Focus a leaf, or a scope (its remembered leaf, else its first). An id that isn't rendered
  /// yet (or is outside the active trap scope) is focused when it appears; returns false then.
  @discardableResult
  public func focus(_ id: FocusID) -> Bool {
    if let leaf = resolve(id) {
      pending = nil
      set(leaf)
      return true
    }
    pending = id
    return false
  }

  /// Next leaf in render order, wrapping. Returns whether focus moved.
  @discardableResult
  public func focusNext() -> Bool { move(by: 1) }

  @discardableResult
  public func focusPrevious() -> Bool { move(by: -1) }

  // MARK: Reconciliation

  /// Called by the host after each render.
  func update(_ newTree: FocusTree) {
    let oldOrder = tree.leaves(in: nil)
    tree = newTree
    // A trap scope (modal) appeared: focus moves into it (to a requested leaf, or its first)
    // and returns when it closes.
    let newTrap = tree.activeTrap.flatMap { trap in
      trap != lastTrap && !lastPath.contains(trap) ? trap : nil
    }
    if let newTrap, let focused { trapReturn[newTrap] = focused }
    if let pending, let leaf = resolve(pending) {
      self.pending = nil
      set(leaf)
      return
    }
    if let newTrap, let leaf = resolve(newTrap) {
      set(leaf)
      return
    }
    if let focused, let leaf = resolve(focused) {
      set(leaf)
      return
    }
    if let lastTrap, tree.entry(lastTrap) == nil,
      let saved = trapReturn.removeValue(forKey: lastTrap), let leaf = resolve(saved)
    {
      set(leaf)
      return
    }
    // The focused leaf is gone: take its nearest survivor in the old order, within the
    // innermost of its scopes that still has leaves.
    let region = regionLeaves
    let scopes: [FocusID?] =
      lastPath.dropLast().reversed().filter { tree.entry($0)?.isScope == true } + [nil]
    for scope in scopes {
      let candidates = (scope.map { tree.leaves(in: $0) } ?? region).filter(region.contains)
      guard !candidates.isEmpty else { continue }
      set(nearest(to: lastPath.last, in: oldOrder, among: candidates))
      return
    }
    if focused != nil {
      focused = nil
      onChange?()
    }
  }

  private func nearest(to leaf: FocusID?, in order: [FocusID], among candidates: [FocusID])
    -> FocusID
  {
    guard let leaf, let index = order.firstIndex(of: leaf) else { return candidates[0] }
    let after = order[(index + 1)...].first(where: candidates.contains)
    return after ?? order[..<index].last(where: candidates.contains) ?? candidates[0]
  }

  private var regionLeaves: [FocusID] { tree.leaves(in: tree.activeTrap) }

  /// The leaf `id` stands for, if it's rendered inside the active trap scope.
  private func resolve(_ id: FocusID) -> FocusID? {
    guard let entry = tree.entry(id) else { return nil }
    let leaves = regionLeaves
    if !entry.isScope { return leaves.contains(id) ? id : nil }
    let inScope = tree.leaves(in: id).filter(leaves.contains)
    if let remembered = remembered[id], inScope.contains(remembered) { return remembered }
    return inScope.first
  }

  private func move(by delta: Int) -> Bool {
    let leaves = regionLeaves
    guard !leaves.isEmpty else { return false }
    guard let focused, let index = leaves.firstIndex(of: focused) else {
      set(delta > 0 ? leaves[0] : leaves[leaves.count - 1])
      return true
    }
    let next = leaves[(index + delta + leaves.count) % leaves.count]
    guard next != focused else { return false }
    set(next)
    return true
  }

  private func set(_ leaf: FocusID) {
    lastPath = tree.path(to: leaf)
    lastTrap = tree.activeTrap
    for scope in lastPath.dropLast() { remembered[scope] = leaf }
    if focused != leaf {
      focused = leaf
      onChange?()
    }
  }
}
