// Markdown-lite document model (ADR 0012). Agent output and docs are parsed once into this tree;
// `VoCoderUI` renders it, and voice can read its plain text without the markup.

/// A parsed markdown-lite document. Parsing never fails: anything it doesn't recognise, or that
/// is malformed (unclosed emphasis, an unclosed fence), stays as text.
public struct MarkdownDocument: Sendable, Equatable {
  public var blocks: [MarkdownBlock]

  public init(blocks: [MarkdownBlock]) { self.blocks = blocks }

  public init(parsing source: String) {
    blocks = MarkdownParser.parse(source)
  }

  /// The text without markup, one line per paragraph, heading, item or code line.
  public var plainText: String { MarkdownBlock.plainText(of: blocks) }
}

public indirect enum MarkdownBlock: Sendable, Equatable {
  /// `level` 1…6.
  case heading(level: Int, [MarkdownInline])
  case paragraph([MarkdownInline])
  /// A fenced code block. `info` is the text after the opening fence (usually the language; empty
  /// if none). An unclosed fence runs to the end of the document.
  case code(info: String, lines: [String])
  case list(MarkdownList)
  case quote([MarkdownBlock])
  case rule
  /// A GFM pipe table, kept as its source lines (not laid out as a grid yet).
  case table(lines: [String])

  static func plainText(of blocks: [MarkdownBlock]) -> String {
    blocks.map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n")
  }

  var plainText: String {
    switch self {
    case .heading(_, let inlines), .paragraph(let inlines): MarkdownInline.plainText(of: inlines)
    case .code(_, let lines), .table(let lines): lines.joined(separator: "\n")
    case .list(let list): list.items.map { Self.plainText(of: $0) }.joined(separator: "\n")
    case .quote(let blocks): Self.plainText(of: blocks)
    case .rule: ""
    }
  }
}

public struct MarkdownList: Sendable, Equatable {
  public var ordered: Bool
  /// The first item's number (ordered lists).
  public var start: Int
  /// Each item's blocks (nested lists are blocks of their item).
  public var items: [[MarkdownBlock]]

  public init(ordered: Bool, start: Int = 1, items: [[MarkdownBlock]]) {
    self.ordered = ordered
    self.start = start
    self.items = items
  }
}

public indirect enum MarkdownInline: Sendable, Equatable {
  case text(String)
  case strong([MarkdownInline])
  case emphasis([MarkdownInline])
  case strikethrough([MarkdownInline])
  case code(String)
  /// Links and images (an image's text is its alt text).
  case link([MarkdownInline], destination: String)
  /// A line break in the source that is just a space when rendered.
  case softBreak
  /// A forced line break (two trailing spaces or a trailing backslash).
  case hardBreak

  static func plainText(of inlines: [MarkdownInline]) -> String {
    inlines.map(\.plainText).joined()
  }

  var plainText: String {
    switch self {
    case .text(let text), .code(let text): text
    case .strong(let inlines), .emphasis(let inlines), .strikethrough(let inlines),
      .link(let inlines, _):
      Self.plainText(of: inlines)
    case .softBreak: " "
    case .hardBreak: "\n"
    }
  }
}
