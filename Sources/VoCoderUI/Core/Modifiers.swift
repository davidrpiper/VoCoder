// View modifiers. Like the bridge's, they apply in call order: `.bold().border()` makes the
// content bold, `.border().bold()` the border too.
import VoCoderUIBridge

/// A size constraint along one axis, in cells.
public enum SizeConstraint: Sendable, Equatable {
  case exactly(Int)
  case atMost(Int)
  case atLeast(Int)

  var bridged: (VCSizeConstraint, Int) {
    switch self {
    case .exactly(let value): (.equal, value)
    case .atMost(let value): (.lessThan, value)
    case .atLeast(let value): (.greaterThan, value)
    }
  }
}

public enum FlexAxis: Sendable {
  /// Grow and shrink on both axes.
  case both
  case horizontal
  case vertical
  /// Reset any flex set further inside.
  case none

  var bridged: VCFlex {
    switch self {
    case .both: .both
    case .horizontal: .horizontal
    case .vertical: .vertical
    case .none: .none
    }
  }
}

public enum Alignment: Sendable {
  case horizontally, vertically, both

  var bridged: VCAlignment {
    switch self {
    case .horizontally: .centerHorizontally
    case .vertically: .centerVertically
    case .both: .center
    }
  }
}

/// A view with a transform applied to its node. Several nodes are stacked vertically first.
struct ModifiedView: View, PrimitiveView {
  typealias Body = Never
  let content: any View
  let transform: @MainActor (VCNode, RenderContext) -> VCNode

  func makeNodes(in context: RenderContext) -> [VCNode] {
    [transform(context.node(for: content), context)]
  }
}

extension View {
  func modified(_ transform: @escaping @MainActor (VCNode, RenderContext) -> VCNode)
    -> some View
  {
    ModifiedView(content: self, transform: transform)
  }

  public func style(_ style: TextStyle) -> some View {
    modified { node, _ in node.styled(style.bridged) }
  }

  public func bold() -> some View { style(.bold) }
  public func dim() -> some View { style(.dim) }
  public func italic() -> some View { style(.italic) }
  public func underlined() -> some View { style(.underlined) }
  public func inverted() -> some View { style(.inverted) }
  public func strikethrough() -> some View { style(.strikethrough) }

  /// Text colour. nil, or a role the theme leaves unset, keeps the inherited colour.
  public func foreground(_ color: Color?) -> some View {
    modified { node, context in
      guard let color, let resolved = context.resolve(color) else { return node }
      return node.foreground(resolved)
    }
  }

  /// Background colour. nil, or a role the theme leaves unset, keeps the inherited colour.
  public func background(_ color: Color?) -> some View {
    modified { node, context in
      guard let color, let resolved = context.resolve(color) else { return node }
      return node.background(resolved)
    }
  }

  /// A border, optionally with a title on its top edge and its own colour (the content's
  /// colours are unaffected).
  public func border(_ style: BorderStyle = .rounded, title: String? = nil, color: Color? = nil)
    -> some View
  {
    modified { node, context in
      node.bordered(style: style.bridged, title: title, color: color.flatMap(context.resolve))
    }
  }

  public func frame(width: SizeConstraint? = nil, height: SizeConstraint? = nil) -> some View {
    modified { node, _ in
      var node = node
      if let (constraint, value) = width?.bridged { node = node.width(constraint, value) }
      if let (constraint, value) = height?.bridged { node = node.height(constraint, value) }
      return node
    }
  }

  /// Take (or give up) the free space of the enclosing stack.
  public func flex(_ axis: FlexAxis = .both) -> some View {
    modified { node, _ in node.flex(axis.bridged) }
  }

  public func centered(_ alignment: Alignment = .both) -> some View {
    modified { node, _ in node.aligned(alignment.bridged) }
  }

  /// An enclosing `ScrollView` keeps this view visible (e.g. the selected row).
  public func keepVisible(_ condition: Bool = true) -> some View {
    modified { node, _ in condition ? node.focusMarker() : node }
  }
}
