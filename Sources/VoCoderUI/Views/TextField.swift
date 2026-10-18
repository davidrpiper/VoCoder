import VoCoderUIBridge

/// A text input: a focusable leaf whose typed keys go to the bridge's input widget (cursor,
/// UTF-8 editing). Read or set its text through `UIHost.text(of:)` / `setText(_:for:)`.
/// Esc, Tab, Shift-Tab, Ctrl-C and Ctrl-Space still reach the host while it is focused.
public struct TextField: View, PrimitiveView {
  public typealias Body = Never
  let id: FocusID
  let placeholder: String
  let multiline: Bool
  let submitsOnEnter: Bool
  let onAction: ActionHandler?
  let onChange: (@MainActor (String) -> Void)?
  let onSubmit: (@MainActor (String) -> Void)?

  /// `onSubmit` fires on Enter in a single-line field; a multi-line field inserts a newline,
  /// unless it `submitsOnEnter` (a prompt: Alt-Enter or `\` + Enter insert the newline).
  public init(
    _ id: FocusID, placeholder: String = "", multiline: Bool = false,
    submitsOnEnter: Bool = false,
    onAction: ActionHandler? = nil,
    onChange: (@MainActor (String) -> Void)? = nil,
    onSubmit: (@MainActor (String) -> Void)? = nil
  ) {
    self.id = id
    self.placeholder = placeholder
    self.multiline = multiline || submitsOnEnter
    self.submitsOnEnter = submitsOnEnter
    self.onAction = onAction
    self.onChange = onChange
    self.onSubmit = onSubmit
  }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    context.focusTree.addLeaf(id, widgetId: id.rawValue, handler: onAction)
    context.widgetHandlers[id.rawValue] = WidgetHandlers(onChange: onChange, onSubmit: onSubmit)
    if submitsOnEnter {
      return [.input(id: id.rawValue, placeholder: placeholder, submitsOnEnter: true)]
    }
    return [.input(id: id.rawValue, placeholder: placeholder, multiline: multiline)]
  }
}
