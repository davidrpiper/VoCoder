import VoCoderUIBridge

/// What a render pass knows: the theme, the focus state of the previous pass, and the focus
/// tree and widget handlers being collected for this one. Read it with `ContextReader`.
@MainActor
public final class RenderContext {
  public let theme: Theme
  let focus: FocusManager
  var focusTree = FocusTree.Builder()
  var widgetHandlers: [String: WidgetHandlers] = [:]
  /// Set when the host renders: views that act on widgets (scrolling) need it.
  let renderer: VCRenderer?

  init(theme: Theme, focus: FocusManager, renderer: VCRenderer?) {
    self.theme = theme
    self.focus = focus
    self.renderer = renderer
  }

  /// The focused leaf, as of the previous render pass.
  public var focused: FocusID? { focus.focused }

  /// Whether `id` is the focused leaf.
  public func isFocused(_ id: FocusID) -> Bool { focus.focused == id }

  /// Whether `id` is the focused leaf or a scope containing it.
  public func containsFocus(_ id: FocusID) -> Bool { focus.path.contains(id) }

  func nodes(for view: any View) -> [VCNode] {
    if let primitive = view as? any PrimitiveView { return primitive.makeNodes(in: self) }
    return nodes(for: view.body)
  }

  /// One node for `view`: several are stacked vertically.
  func node(for view: any View) -> VCNode {
    let nodes = nodes(for: view)
    return nodes.count == 1 ? nodes[0] : .vbox(nodes)
  }

  func resolve(_ color: Color) -> VCColor? { color.resolved(in: theme) }
}

struct WidgetHandlers {
  var onChange: (@MainActor (String) -> Void)?
  var onSubmit: (@MainActor (String) -> Void)?
}

/// Gives a view's content access to the render context (theme, focus).
public struct ContextReader<Content: View>: View, PrimitiveView {
  public typealias Body = Never
  let content: (RenderContext) -> Content

  public init(@ViewBuilder _ content: @escaping (RenderContext) -> Content) {
    self.content = content
  }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    context.nodes(for: content(context))
  }
}
