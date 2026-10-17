/// A column of a `TableView`.
public struct TableColumn<Item> {
  public enum Width: Sendable, Equatable {
    case fixed(Int)
    /// Takes the remaining width. Rows stay aligned with at most one flexible column.
    case flexible
  }

  let title: String
  let width: Width
  let value: (Item) -> String

  public init(_ title: String, width: Width, value: @escaping (Item) -> String) {
    self.title = title
    self.width = width
    self.value = value
  }
}

/// A `ListView` laid out in columns under a fixed header row.
public struct TableView<Item>: View {
  let id: FocusID
  let state: ListState
  let items: [Item]
  let columns: [TableColumn<Item>]
  let onActivate: (@MainActor (Int) -> Void)?

  public init(
    _ id: FocusID, state: ListState, items: [Item], columns: [TableColumn<Item>],
    onActivate: (@MainActor (Int) -> Void)? = nil
  ) {
    self.id = id
    self.state = state
    self.items = items
    self.columns = columns
    self.onActivate = onActivate
  }

  public var body: some View {
    VStack {
      cells(columns.map(\.title)).bold().foreground(.muted)
      ListView(id, state: state, items: items, onActivate: onActivate) { item, _ in
        cells(columns.map { $0.value(item) })
      }.flex()
    }
  }

  private func cells(_ values: [String]) -> some View {
    HStack {
      for (column, value) in zip(columns, values) {
        switch column.width {
        case .fixed(let width): Text(value).frame(width: .exactly(width))
        case .flexible: Text(value).flex(.horizontal)
        }
        Text(" ")
      }
    }
  }
}
