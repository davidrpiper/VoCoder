// Markdown-lite rendering (ADR 0012): `MarkdownDocument` (parsed in Core) → bridge nodes. Inline
// text becomes words in a `flow` node, so styled text wraps; code blocks and tables never wrap.
import VoCoderCore
import VoCoderUIBridge

/// Children laid out like words: one space apart, wrapping at the available width. A child wider
/// than a line is broken across lines. Each child is one unbreakable word (style it as a whole,
/// or use an `HStack` of styled `Text`s for a word that mixes styles).
public struct Flow: View, PrimitiveView {
  public typealias Body = Never
  let content: ViewGroup

  public init(@ViewBuilder _ content: () -> ViewGroup) { self.content = content() }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    [.flow(content.views.map { context.node(for: $0) })]
  }
}

/// Markdown-lite: headings, fenced code, nested lists, quotes, rules, pipe tables (as lines),
/// `**bold**`, `*italic*`, `~~strike~~`, `` `code` `` and links (shown as their text). Malformed
/// markup renders as text.
public struct Markdown: View, PrimitiveView {
  public typealias Body = Never
  let document: MarkdownDocument

  public init(_ source: String) { document = MarkdownDocument(parsing: source) }

  /// For text that is shown repeatedly (agent messages): parse once, render many times.
  public init(document: MarkdownDocument) { self.document = document }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    [MarkdownRenderer(context: context).blocks(document.blocks, tight: false, listLevel: 0)]
  }
}

@MainActor
private struct MarkdownRenderer {
  let context: RenderContext

  /// Bullets by nesting level, cycling.
  static let bullets = ["•", "◦", "▪"]

  /// `tight`: no blank line between blocks (inside list items).
  func blocks(_ blocks: [MarkdownBlock], tight: Bool, listLevel: Int) -> VCNode {
    var nodes: [VCNode] = []
    for block in blocks {
      if !tight, !nodes.isEmpty { nodes.append(.text("")) }
      nodes.append(self.block(block, listLevel: listLevel))
    }
    return nodes.count == 1 ? nodes[0] : .vbox(nodes)
  }

  private func block(_ block: MarkdownBlock, listLevel: Int) -> VCNode {
    switch block {
    case .heading(let level, let inlines):
      let base: RunStyle =
        switch level {
        case 1: RunStyle(style: .bold, foreground: .accent)
        case 2: RunStyle(style: .bold)
        default: RunStyle(style: .bold, foreground: .muted)
        }
      return text(inlines, base: base)
    case .paragraph(let inlines):
      return text(inlines, base: RunStyle())
    case .code(_, let lines):
      return codeBlock(lines)
    case .table(let lines):
      return .vbox(lines.map { .text($0) })
    case .list(let list):
      return self.list(list, level: listLevel)
    case .quote(let inner):
      let bar = color(VCNode.separator(), .border)
      let content = blocks(inner, tight: false, listLevel: listLevel).flex(.horizontal)
      return .hbox([bar, .text(" "), content])
    case .rule:
      return color(VCNode.separator(), .border)
    }
  }

  /// One space of padding on the left; the background spans the full width; lines never wrap.
  private func codeBlock(_ lines: [String]) -> VCNode {
    let rows = (lines.isEmpty ? [""] : lines).map { VCNode.text(" " + $0) }
    return background(VCNode.vbox(rows), .codeBackground)
  }

  private func list(_ list: MarkdownList, level: Int) -> VCNode {
    let markers = list.items.indices.map { index in
      list.ordered
        ? "\(list.start + index)." : Self.bullets[level % Self.bullets.count]
    }
    // Numbers right-aligned so the items' text lines up ("9." and "10.").
    let width = markers.map(\.count).max() ?? 0
    let rows = zip(markers, list.items).map { marker, item -> VCNode in
      let padded = String(repeating: " ", count: width - marker.count) + marker + " "
      let content = blocks(item, tight: true, listLevel: level + 1).flex(.horizontal)
      return .hbox([color(.text(padded), .muted), content])
    }
    return .vbox(rows)
  }

  // MARK: Inline text

  /// A flow per line (hard breaks start a new one).
  private func text(_ inlines: [MarkdownInline], base: RunStyle) -> VCNode {
    var collector = WordCollector()
    collector.add(inlines, style: base)
    let lines = collector.finish().map { words in
      words.isEmpty ? VCNode.text("") : .flow(words.map(word))
    }
    return lines.count == 1 ? lines[0] : .vbox(lines)
  }

  private func word(_ runs: [Run]) -> VCNode {
    let nodes = runs.map { run in
      var node = VCNode.text(run.text)
      if !run.style.style.isEmpty { node = node.styled(run.style.style.bridged) }
      if let foreground = run.style.foreground { node = color(node, foreground) }
      if let background = run.style.background { node = self.background(node, background) }
      return node
    }
    return nodes.count == 1 ? nodes[0] : .hbox(nodes)
  }

  private func color(_ node: VCNode, _ color: Color) -> VCNode {
    context.resolve(color).map { node.foreground($0) } ?? node
  }

  private func background(_ node: VCNode, _ color: Color) -> VCNode {
    context.resolve(color).map { node.background($0) } ?? node
  }
}

private struct RunStyle {
  var style: TextStyle = []
  var foreground: Color?
  var background: Color?

  func adding(_ extra: TextStyle, foreground: Color? = nil, background: Color? = nil) -> RunStyle {
    RunStyle(
      style: style.union(extra), foreground: foreground ?? self.foreground,
      background: background ?? self.background)
  }
}

/// Text in one style, without breaks (inline code may contain spaces).
private struct Run {
  var text: String
  var style: RunStyle
}

/// Turns inlines into lines of words; a word is the runs between two spaces. Inline code is kept
/// whole, so `git status` doesn't wrap in the middle.
private struct WordCollector {
  private var lines: [[[Run]]] = []
  private var words: [[Run]] = []
  private var word: [Run] = []

  mutating func add(_ inlines: [MarkdownInline], style: RunStyle) {
    for inline in inlines {
      switch inline {
      case .text(let text):
        for character in text {
          if character.isWhitespace {
            endWord()
          } else {
            append(String(character), style: style)
          }
        }
      case .strong(let inner): add(inner, style: style.adding(.bold))
      case .emphasis(let inner): add(inner, style: style.adding(.italic))
      case .strikethrough(let inner): add(inner, style: style.adding(.strikethrough))
      case .link(let inner, _): add(inner, style: style.adding(.underlined, foreground: .accent))
      case .code(let code):
        // A new run even when the style matches its neighbour's, so it stays one piece.
        word.append(Run(text: code, style: style.adding([], background: .codeBackground)))
      case .softBreak: endWord()
      case .hardBreak:
        endWord()
        lines.append(words)
        words = []
      }
    }
  }

  mutating func finish() -> [[[Run]]] {
    endWord()
    lines.append(words)
    return lines
  }

  private mutating func append(_ text: String, style: RunStyle) {
    if let last = word.last, last.style.matches(style), last.style.background == nil {
      word[word.count - 1].text += text
    } else {
      word.append(Run(text: text, style: style))
    }
  }

  private mutating func endWord() {
    if !word.isEmpty { words.append(word) }
    word = []
  }
}

extension RunStyle {
  fileprivate func matches(_ other: RunStyle) -> Bool {
    style == other.style && foreground == other.foreground && background == other.background
  }
}
