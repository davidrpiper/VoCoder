import VoCoderUIBridge

/// A focusable leaf. `content` receives whether it is focused. A leaf shouldn't contain other
/// focusable views; group those with `focusScope` instead.
public struct Focusable<Content: View>: View, PrimitiveView {
  public typealias Body = Never
  let id: FocusID
  let onAction: ActionHandler?
  let content: (Bool) -> Content

  public init(
    _ id: FocusID, onAction: ActionHandler? = nil,
    @ViewBuilder content: @escaping (_ isFocused: Bool) -> Content
  ) {
    self.id = id
    self.onAction = onAction
    self.content = content
  }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    context.focusTree.addLeaf(id, widgetId: nil, handler: onAction)
    return context.nodes(for: content(context.isFocused(id)))
  }
}

struct FocusScopeView: View, PrimitiveView {
  typealias Body = Never
  let content: any View
  let id: FocusID
  let trap: Bool
  let onAction: ActionHandler?

  func makeNodes(in context: RenderContext) -> [VCNode] {
    context.focusTree.beginScope(id, trap: trap, handler: onAction)
    defer { context.focusTree.endScope() }
    return context.nodes(for: content)
  }
}

extension View {
  /// Groups the focusable views inside: focusing the scope focuses its last-focused leaf, and
  /// `onAction` gets the actions its focused descendants don't handle. A `trap` scope keeps
  /// focus inside while it is rendered (modals).
  public func focusScope(_ id: FocusID, trap: Bool = false, onAction: ActionHandler? = nil)
    -> some View
  {
    FocusScopeView(content: self, id: id, trap: trap, onAction: onAction)
  }
}
