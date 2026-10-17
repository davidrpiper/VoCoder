// Built-in content and layout views.
import VoCoderUIBridge

/// A single line of text; never wraps (clipped to the available width).
public struct Text: View, PrimitiveView {
  public typealias Body = Never
  let string: String

  public init(_ string: String) { self.string = string }

  func makeNodes(in context: RenderContext) -> [VCNode] { [.text(string)] }
}

/// Text that wraps at word boundaries to the available width.
public struct Paragraph: View, PrimitiveView {
  public typealias Body = Never
  let string: String

  public init(_ string: String) { self.string = string }

  func makeNodes(in context: RenderContext) -> [VCNode] { [.paragraph(string)] }
}

/// Children top to bottom; each gets the full width.
public struct VStack: View, PrimitiveView {
  public typealias Body = Never
  let content: ViewGroup

  public init(@ViewBuilder _ content: () -> ViewGroup) { self.content = content() }

  func makeNodes(in context: RenderContext) -> [VCNode] { [.vbox(context.nodes(for: content))] }
}

/// Children left to right; each gets the full height.
public struct HStack: View, PrimitiveView {
  public typealias Body = Never
  let content: ViewGroup

  public init(@ViewBuilder _ content: () -> ViewGroup) { self.content = content() }

  func makeNodes(in context: RenderContext) -> [VCNode] { [.hbox(context.nodes(for: content))] }
}

/// Children drawn on top of each other, later ones on top.
public struct ZStack: View, PrimitiveView {
  public typealias Body = Never
  let content: ViewGroup

  public init(@ViewBuilder _ content: () -> ViewGroup) { self.content = content() }

  func makeNodes(in context: RenderContext) -> [VCNode] { [.dbox(context.nodes(for: content))] }
}

/// Takes the free space in a stack.
public struct Spacer: View, PrimitiveView {
  public typealias Body = Never
  public init() {}
  func makeNodes(in context: RenderContext) -> [VCNode] { [.filler()] }
}

/// A line across a stack: horizontal in a `VStack`, vertical in an `HStack`.
public struct Divider: View, PrimitiveView {
  public typealias Body = Never
  let color: Color?

  public init(color: Color? = .border) { self.color = color }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    let node = VCNode.separator()
    return [color.flatMap(context.resolve).map { node.foreground($0) } ?? node]
  }
}

/// A progress bar for `progress` in 0…1.
public struct Gauge: View, PrimitiveView {
  public typealias Body = Never
  let progress: Double
  let vertical: Bool

  public init(_ progress: Double, vertical: Bool = false) {
    self.progress = progress
    self.vertical = vertical
  }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    [.gauge(Float(progress), axis: vertical ? .vertical : .horizontal)]
  }
}

/// One frame of a spinner. The caller advances `frame` over time.
public struct Spinner: View, PrimitiveView {
  public typealias Body = Never
  let frame: Int
  let charset: Int

  /// `charset` selects one of FTXUI's glyph sets (0…22); 15 is braille dots.
  public init(frame: Int, charset: Int = 15) {
    self.frame = frame
    self.charset = charset
  }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    [.spinner(charset: charset, frame: frame)]
  }
}

/// A row of tab titles with the selected one highlighted.
public struct TabBar: View, PrimitiveView {
  public typealias Body = Never
  let titles: [String]
  let selected: Int

  public init(_ titles: [String], selected: Int) {
    self.titles = titles
    self.selected = selected
  }

  func makeNodes(in context: RenderContext) -> [VCNode] { [.tabBar(titles, selected: selected)] }
}

/// A static grid of cells whose columns size to their content (for selectable rows, use
/// `TableView`). Rows may have different lengths.
public struct Grid: View, PrimitiveView {
  public typealias Body = Never
  let rows: [[any View]]
  let header: Bool
  let border: Bool
  let columnSeparators: Bool

  public init(
    _ rows: [[any View]], header: Bool = false, border: Bool = false,
    columnSeparators: Bool = false
  ) {
    self.rows = rows
    self.header = header
    self.border = border
    self.columnSeparators = columnSeparators
  }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    var options: VCTableOptions = []
    if header { options.insert(.header) }
    if border { options.insert(.border) }
    if columnSeparators { options.insert(.columnSeparators) }
    return [.table(rows.map { $0.map { context.node(for: $0) } }, options: options)]
  }
}

/// Children left to right at their natural widths. When they don't fit, the child at
/// `keepingVisible` and as many neighbours as fit are shown, with "‹n" / "n›" markers counting
/// the hidden ones (the tab bar).
public struct Strip: View, PrimitiveView {
  public typealias Body = Never
  let keep: Int
  let content: ViewGroup

  public init(keepingVisible index: Int, @ViewBuilder _ content: () -> ViewGroup) {
    keep = index
    self.content = content()
  }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    [.strip(context.nodes(for: content), keepingVisible: keep)]
  }
}
