import Observation

/// Selection of a `ListView` / `TableView`; keep it in the view model.
@MainActor
@Observable
public final class ListState {
  /// Clamped to the items when drawn and moved, so it may be stale after the data changes.
  public var selection: Int
  /// Rows moved by page up/down. The viewport height isn't known in Swift.
  public var pageSize: Int

  public init(selection: Int = 0, pageSize: Int = 10) {
    self.selection = selection
    self.pageSize = pageSize
  }

  /// The selected index among `count` items, nil when there are none.
  public func selectedIndex(count: Int) -> Int? {
    count == 0 ? nil : min(max(selection, 0), count - 1)
  }

  /// Applies a movement action; returns false for actions a list doesn't handle.
  @discardableResult
  public func perform(_ action: UIAction, count: Int) -> Bool {
    let current = selectedIndex(count: count) ?? 0
    let target: Int
    switch action {
    case .moveUp: target = current - 1
    case .moveDown: target = current + 1
    case .pageUp: target = current - pageSize
    case .pageDown: target = current + pageSize
    case .moveToFirst: target = 0
    case .moveToLast: target = count - 1
    default: return false
    }
    // Moves at the ends are still handled, so they don't bubble to an enclosing scope.
    let clamped = min(max(target, 0), max(count - 1, 0))
    if clamped != selection { selection = clamped }
    return true
  }
}

/// How a row is drawn.
public struct RowState: Sendable, Equatable {
  public let index: Int
  public let isSelected: Bool
  /// Whether the list has focus (the selection is drawn brighter then).
  public let listFocused: Bool
}

/// A focusable, scrolling list of rich rows with a selection. Movement actions move the
/// selection; `activate` (Enter) calls `onActivate` with the selected index.
public struct ListView<Item, Row: View>: View {
  let id: FocusID
  let state: ListState
  let items: [Item]
  let emptyText: String
  let onActivate: (@MainActor (Int) -> Void)?
  let row: (Item, RowState) -> Row

  public init(
    _ id: FocusID, state: ListState, items: [Item], emptyText: String = "Nothing here",
    onActivate: (@MainActor (Int) -> Void)? = nil,
    @ViewBuilder row: @escaping (Item, RowState) -> Row
  ) {
    self.id = id
    self.state = state
    self.items = items
    self.emptyText = emptyText
    self.onActivate = onActivate
    self.row = row
  }

  public var body: some View {
    let count = items.count
    let selected = state.selectedIndex(count: count)
    Focusable(id, onAction: handler(count: count)) { focused in
      if items.isEmpty {
        Text(emptyText).foreground(.muted)
      } else {
        ScrollView(id.appending("scroll")) {
          for (index, item) in items.enumerated() {
            let isSelected = index == selected
            row(item, RowState(index: index, isSelected: isSelected, listFocused: focused))
              .foreground(isSelected && focused ? .selectionText : nil)
              .background(isSelected ? (focused ? .selection : .inactiveSelection) : nil)
              .keepVisible(isSelected)
          }
        }
      }
    }
  }

  private func handler(count: Int) -> ActionHandler {
    { [state, onActivate] action in
      if action == .activate {
        guard let onActivate, let index = state.selectedIndex(count: count) else { return false }
        onActivate(index)
        return true
      }
      return state.perform(action, count: count)
    }
  }
}
