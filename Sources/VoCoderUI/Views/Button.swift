/// A focusable button: "[ Title ]", highlighted when focused; Enter (`ui.activate`) presses it.
public struct Button: View {
  let id: FocusID
  let title: String
  let action: @MainActor () -> Void

  public init(_ id: FocusID, _ title: String, action: @escaping @MainActor () -> Void) {
    self.id = id
    self.title = title
    self.action = action
  }

  public var body: some View {
    let press: ActionHandler = { [action] uiAction in
      guard uiAction == .activate else { return false }
      action()
      return true
    }
    Focusable(id, onAction: press) { focused in
      Text("[ \(title) ]")
        .foreground(focused ? .selectionText : nil)
        .background(focused ? .selection : nil)
        .style(focused ? .bold : [])
    }
  }
}
