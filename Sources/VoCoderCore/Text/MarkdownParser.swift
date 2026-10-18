// Hand-written markdown-lite parser (ADR 0004, ADR 0012): a CommonMark-like subset, lenient where
// agents are sloppy (list indentation) and never failing. Blocks are found line by line;
// container blocks (quotes, list items) strip their markers and parse their lines recursively.
// Inlines are parsed per block over characters.

enum MarkdownParser {
  static func parse(_ source: String) -> [MarkdownBlock] {
    // "\r\n" is one Character, so it must be normalised before splitting on "\n".
    let normalised = source.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
    let lines = normalised.split(separator: "\n", omittingEmptySubsequences: false)
      .map { expandTabs(String($0)) }
    return BlockParser.parse(lines)
  }

  /// Tabs become spaces up to the next multiple of 4 (indentation and terminal cell widths).
  static func expandTabs(_ line: String) -> String {
    guard line.contains("\t") else { return line }
    var out = ""
    var column = 0
    for character in line {
      if character == "\t" {
        let spaces = 4 - column % 4
        out += String(repeating: " ", count: spaces)
        column += spaces
      } else {
        out.append(character)
        column += 1
      }
    }
    return out
  }
}

// MARK: - Blocks

private struct ListMarker {
  var ordered: Bool
  var number: Int
  /// The marker's own indentation.
  var indent: Int
  /// Where the item's content starts; continuation lines are de-indented by up to this much.
  var contentIndent: Int
  var content: String
}

private enum LineKind {
  case blank
  case fence(character: Character, count: Int, indent: Int, info: String)
  case heading(level: Int, text: String)
  case rule
  case quote
  case listItem(ListMarker)
  case text
}

private struct BlockParser {
  let lines: [String]
  var index = 0

  /// Quotes and list items nest at most this deep; deeper markers are text. Bounds recursion
  /// (and the stack) on input like 2000 `> `.
  static let maxDepth = 32

  let depth: Int

  static func parse(_ lines: [String], depth: Int = 0) -> [MarkdownBlock] {
    var parser = BlockParser(lines: lines, depth: depth)
    return parser.parseBlocks()
  }

  private init(lines: [String], depth: Int) {
    self.lines = lines
    self.depth = depth
  }

  private mutating func parseBlocks() -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    while index < lines.count {
      let line = lines[index]
      switch classify(line) {
      case .blank:
        index += 1
      case .fence(let character, let count, let indent, let info):
        blocks.append(fencedCode(character: character, count: count, indent: indent, info: info))
      case .heading(let level, let text):
        blocks.append(.heading(level: level, InlineParser.parse(text)))
        index += 1
      case .rule:
        blocks.append(.rule)
        index += 1
      case .quote:
        blocks.append(quote())
      case .listItem(let marker):
        blocks.append(list(startingWith: marker))
      case .text:
        blocks.append(isTableStart(index) ? table() : paragraph())
      }
    }
    return blocks
  }

  // MARK: Leaf blocks

  private mutating func fencedCode(
    character: Character, count: Int, indent: Int, info: String
  ) -> MarkdownBlock {
    index += 1
    var code: [String] = []
    while index < lines.count {
      let line = lines[index]
      index += 1
      if isClosingFence(line, character: character, count: count) { break }
      code.append(removingIndent(line, upTo: indent))
    }
    return .code(info: info, lines: code)
  }

  private func isClosingFence(_ line: String, character: Character, count: Int) -> Bool {
    guard indentation(of: line) <= 3 else { return false }
    let trimmed = line.trimmingSpaces()
    return trimmed.count >= count && trimmed.allSatisfy { $0 == character }
  }

  private mutating func paragraph() -> MarkdownBlock {
    var text = [lines[index].droppingLeadingSpaces()]
    index += 1
    while index < lines.count {
      let line = lines[index]
      if let level = setextLevel(line) {
        index += 1
        return .heading(level: level, InlineParser.parse(joined(text)))
      }
      if interruptsParagraph(line) { break }
      text.append(line.droppingLeadingSpaces())
      index += 1
    }
    return .paragraph(InlineParser.parse(joined(text)))
  }

  /// Paragraph lines joined for the inline parser, which turns the newlines into breaks.
  private func joined(_ text: [String]) -> String {
    var result = text.joined(separator: "\n")
    while result.last == " " { result.removeLast() }
    return result
  }

  private func setextLevel(_ line: String) -> Int? {
    guard indentation(of: line) <= 3 else { return nil }
    let trimmed = line.trimmingSpaces()
    guard let first = trimmed.first, first == "=" || first == "-" else { return nil }
    guard trimmed.allSatisfy({ $0 == first }) else { return nil }
    return first == "=" ? 1 : 2
  }

  private func interruptsParagraph(_ line: String) -> Bool {
    switch classify(line) {
    case .blank, .fence, .heading, .rule, .quote: return true
    // As in CommonMark, only bullets and "1." start a list inside a paragraph ("in 2024. Then"
    // wrapped onto a new line is not a list), and empty items don't.
    case .listItem(let marker):
      return !marker.content.isEmpty && (!marker.ordered || marker.number == 1)
    case .text: return isTableStart(index)
    }
  }

  // MARK: Tables

  /// A row with a `|` followed by a delimiter row (`|---|:--:|`).
  private func isTableStart(_ at: Int) -> Bool {
    guard at + 1 < lines.count, lines[at].contains("|") else { return false }
    let delimiter = lines[at + 1].trimmingSpaces()
    return delimiter.contains("|") && delimiter.contains("-")
      && delimiter.allSatisfy { "|-: ".contains($0) }
  }

  private mutating func table() -> MarkdownBlock {
    var rows = [lines[index], lines[index + 1]].map { $0.droppingLeadingSpaces() }
    index += 2
    while index < lines.count, lines[index].contains("|"), !lines[index].isBlank {
      rows.append(lines[index].droppingLeadingSpaces())
      index += 1
    }
    return .table(lines: rows)
  }

  // MARK: Containers

  private mutating func quote() -> MarkdownBlock {
    var inner: [String] = []
    while index < lines.count {
      let line = lines[index]
      if case .quote = classify(line) {
        var rest = Substring(line.droppingLeadingSpaces().dropFirst())
        if rest.first == " " { rest = rest.dropFirst() }
        inner.append(String(rest))
      } else if isLazyContinuation(line, after: inner) {
        inner.append(line)
      } else {
        break
      }
      index += 1
    }
    return .quote(BlockParser.parse(inner, depth: depth + 1))
  }

  private mutating func list(startingWith first: ListMarker) -> MarkdownBlock {
    var items: [[MarkdownBlock]] = []
    while index < lines.count, case .listItem(let marker) = classify(lines[index]),
      marker.ordered == first.ordered
    {
      index += 1
      var inner = [marker.content]
      // Lenient about agents' indentation: two spaces past the marker are enough to stay in the
      // item, even when the content starts further right ("1. " is 3 wide).
      let required = min(marker.contentIndent, marker.indent + 2)
      while index < lines.count {
        let line = lines[index]
        if line.isBlank {
          inner.append("")
        } else if indentation(of: line) >= required {
          inner.append(removingIndent(line, upTo: marker.contentIndent))
        } else if isLazyContinuation(line, after: inner) {
          inner.append(line.droppingLeadingSpaces())
        } else {
          break
        }
        index += 1
      }
      // Trailing blank lines belong between items, not to this one.
      while inner.last?.isBlank == true, inner.count > 1 {
        inner.removeLast()
        index -= 1
      }
      items.append(BlockParser.parse(inner, depth: depth + 1))
      // A blank line before the next item is fine; anything else ends the list.
      while index < lines.count, lines[index].isBlank,
        index + 1 < lines.count, case .listItem(let next) = classify(lines[index + 1]),
        next.ordered == first.ordered
      {
        index += 1
      }
    }
    return .list(MarkdownList(ordered: first.ordered, start: first.number, items: items))
  }

  /// A non-indented line continuing the paragraph that ends `inner` (CommonMark's "lazy" lines).
  private func isLazyContinuation(_ line: String, after inner: [String]) -> Bool {
    guard let last = inner.last, !last.isBlank else { return false }
    guard case .text = classify(line) else { return false }
    if case .fence = classify(last) { return false }
    return !isTableStart(index)
  }

  // MARK: Line classification

  private func classify(_ line: String) -> LineKind {
    if line.isBlank { return .blank }
    let indent = indentation(of: line)
    guard indent <= 3 else { return .text }
    let rest = Substring(line.dropFirst(indent))
    if let fence = fence(rest, indent: indent) { return fence }
    if let heading = heading(rest) { return heading }
    if isRule(rest) { return .rule }
    guard depth < Self.maxDepth else { return .text }
    if rest.first == ">" { return .quote }
    if let marker = listMarker(rest, indent: indent) { return .listItem(marker) }
    return .text
  }

  private func fence(_ rest: Substring, indent: Int) -> LineKind? {
    guard let character = rest.first, character == "`" || character == "~" else { return nil }
    let count = rest.prefix { $0 == character }.count
    guard count >= 3 else { return nil }
    let info = rest.dropFirst(count).trimmingSpaces()
    // A backtick fence's info string can't contain backticks (that's inline code).
    if character == "`" && info.contains("`") { return nil }
    return .fence(character: character, count: count, indent: indent, info: info)
  }

  private func heading(_ rest: Substring) -> LineKind? {
    let level = rest.prefix { $0 == "#" }.count
    guard (1...6).contains(level) else { return nil }
    let after = rest.dropFirst(level)
    guard after.isEmpty || after.first == " " else { return nil }
    var text = after.trimmingSpaces()
    // An optional closing sequence: "## Title ##".
    let closing = text.reversed().prefix { $0 == "#" }.count
    if closing == text.count {
      text = ""
    } else if closing > 0, text.dropLast(closing).last == " " {
      text = String(text.dropLast(closing)).trimmingSpaces()
    }
    return .heading(level: level, text: text)
  }

  private func isRule(_ rest: Substring) -> Bool {
    let marks = rest.filter { $0 != " " }
    guard let first = marks.first, "-*_".contains(first), marks.count >= 3 else { return false }
    return marks.allSatisfy { $0 == first }
  }

  private func listMarker(_ rest: Substring, indent: Int) -> ListMarker? {
    var ordered = false
    var number = 1
    var width: Int
    if let first = rest.first, "-*+".contains(first) {
      width = 1
    } else {
      let digits = rest.prefix { $0.isASCII && $0.isNumber }
      guard (1...9).contains(digits.count), let value = Int(digits) else { return nil }
      let delimiter = rest.dropFirst(digits.count).first
      guard delimiter == "." || delimiter == ")" else { return nil }
      ordered = true
      number = value
      width = digits.count + 1
    }
    let after = rest.dropFirst(width)
    if after.isEmpty || after.allSatisfy({ $0 == " " }) {
      return ListMarker(
        ordered: ordered, number: number, indent: indent, contentIndent: indent + width + 1,
        content: "")
    }
    let spaces = after.prefix { $0 == " " }.count
    guard spaces >= 1 else { return nil }
    // More than 4 spaces: the content starts after one (CommonMark).
    let gap = spaces > 4 ? 1 : spaces
    return ListMarker(
      ordered: ordered, number: number, indent: indent, contentIndent: indent + width + gap,
      content: String(after.dropFirst(gap)))
  }

  // MARK: Helpers

  private func indentation(of line: String) -> Int { line.prefix { $0 == " " }.count }

  private func removingIndent(_ line: String, upTo count: Int) -> String {
    String(line.dropFirst(min(count, indentation(of: line))))
  }
}

extension StringProtocol {
  fileprivate var isBlank: Bool { allSatisfy { $0 == " " } }

  fileprivate func droppingLeadingSpaces() -> String { String(drop { $0 == " " }) }

  fileprivate func trimmingSpaces() -> String {
    String(drop { $0 == " " }.reversed().drop { $0 == " " }.reversed())
  }
}

// MARK: - Inlines

/// Parses one block's text. Openers without a matching closer stay literal. Searches for closers
/// look at most `maxSpan` characters ahead, which bounds the cost of pathological input.
struct InlineParser {
  static let maxSpan = 4096
  /// Emphasis and links nest at most this deep; deeper delimiters are text.
  static let maxDepth = 32

  private let chars: [Character]

  static func parse(_ text: String) -> [MarkdownInline] {
    let parser = InlineParser(chars: Array(text))
    return parser.parse(0..<parser.chars.count, depth: 0)
  }

  private func parse(_ range: Range<Int>, depth: Int) -> [MarkdownInline] {
    let nests = depth < Self.maxDepth
    var output = Output()
    var i = range.lowerBound
    let end = range.upperBound
    while i < end {
      let c = chars[i]
      switch c {
      case "\\":
        if i + 1 < end, chars[i + 1] == "\n" {
          output.append(.hardBreak)
          i += 2
        } else if i + 1 < end, chars[i + 1].isASCIIPunctuation {
          output.append(chars[i + 1])
          i += 2
        } else {
          output.append(c)
          i += 1
        }
      case "\n":
        // Two or more trailing spaces make a hard break; any trailing spaces are dropped.
        let trailing = output.trimTrailingSpaces()
        output.append(trailing >= 2 ? .hardBreak : .softBreak)
        i += 1
      case "`":
        let count = run(at: i, end: end)
        if let close = codeClose(from: i + count, count: count, end: end) {
          output.append(.code(codeContent(i + count..<close)))
          i = close + count
        } else {
          output.append(String(repeating: "`", count: count))
          i += count
        }
      case "*", "_", "~":
        if nests, let (inline, next) = delimited(at: i, end: end, depth: depth) {
          output.append(inline)
          i = next
        } else {
          output.append(c)
          i += 1
        }
      case "[", "!":
        if nests, let (inline, next) = link(at: i, end: end, depth: depth) {
          output.append(inline)
          i = next
        } else {
          output.append(c)
          i += 1
        }
      case "<":
        if let (inline, next) = autolink(at: i, end: end) {
          output.append(inline)
          i = next
        } else {
          output.append(c)
          i += 1
        }
      default:
        output.append(c)
        i += 1
      }
    }
    return output.finish()
  }

  // MARK: Emphasis and strikethrough

  /// `**strong**`, `*emphasis*` (also with `_`), `~~strikethrough~~`, starting at `i`. A run of
  /// two that finds no closer of two returns nil, so the caller emits one literal character and
  /// the next one is tried as a single opener (`**a*` is `*` + emphasis, as in CommonMark).
  private func delimited(at i: Int, end: Int, depth: Int) -> (MarkdownInline, Int)? {
    let c = chars[i]
    let count = run(at: i, end: end)
    guard isLeftFlanking(i, i + count, end: end) else { return nil }
    let width: Int
    switch c {
    case "~": width = 2
    default: width = min(count, 2)
    }
    guard count >= width else { return nil }
    let contentStart = i + width
    guard let close = closer(of: c, width: width, from: contentStart, end: end) else {
      return nil
    }
    let content = parse(contentStart..<close, depth: depth + 1)
    let inline: MarkdownInline =
      switch (c, width) {
      case ("~", _): .strikethrough(content)
      case (_, 2): .strong(content)
      default: .emphasis(content)
      }
    return (inline, close + width)
  }

  /// The start of the closing delimiter: the last `width` characters of a right-flanking run.
  /// Runs of the other width are skipped, so `*a **b** c*` closes at the last `*`. Runs of three
  /// match both (`***a***`).
  private func closer(of c: Character, width: Int, from start: Int, end: Int) -> Int? {
    var j = start
    let limit = min(end, start + Self.maxSpan)
    while j < limit {
      switch chars[j] {
      case "\\":
        j += 2
      case "`":
        let count = run(at: j, end: end)
        j = codeClose(from: j + count, count: count, end: end).map { $0 + count } ?? j + count
      case c:
        let count = run(at: j, end: end)
        let runEnd = j + count
        let matches = width == 1 ? count != 2 : count >= 2
        if matches, runEnd - width > start, isRightFlanking(j, runEnd, end: end) {
          return runEnd - width
        }
        j = runEnd
      default:
        j += 1
      }
    }
    return nil
  }

  /// The run can open: not followed by whitespace; `_` also not preceded by a letter or digit.
  private func isLeftFlanking(_ start: Int, _ runEnd: Int, end: Int) -> Bool {
    guard runEnd < end, !chars[runEnd].isWhitespace else { return false }
    if chars[start] == "_", start > 0, chars[start - 1].isLetterOrDigit { return false }
    return true
  }

  /// The run can close: not preceded by whitespace; `_` also not followed by a letter or digit.
  private func isRightFlanking(_ start: Int, _ runEnd: Int, end: Int) -> Bool {
    guard start > 0, !chars[start - 1].isWhitespace else { return false }
    if chars[start] == "_", runEnd < end, chars[runEnd].isLetterOrDigit { return false }
    return true
  }

  // MARK: Code spans

  /// The start of a closing backtick run of exactly `count`.
  private func codeClose(from start: Int, count: Int, end: Int) -> Int? {
    var j = start
    let limit = min(end, start + Self.maxSpan)
    while j < limit {
      guard chars[j] == "`" else {
        j += 1
        continue
      }
      let length = run(at: j, end: end)
      if length == count { return j }
      j += length
    }
    return nil
  }

  /// Newlines become spaces; one space is stripped from each end if both have one.
  private func codeContent(_ range: Range<Int>) -> String {
    var text = String(chars[range]).replacing("\n", with: " ")
    if text.count >= 2, text.first == " ", text.last == " ", text.contains(where: { $0 != " " }) {
      text = String(text.dropFirst().dropLast())
    }
    return text
  }

  // MARK: Links

  /// `[text](destination "title")` or `![alt](source)`; reference links stay literal.
  private func link(at i: Int, end: Int, depth: Int) -> (MarkdownInline, Int)? {
    var open = i
    if chars[i] == "!" {
      guard i + 1 < end, chars[i + 1] == "[" else { return nil }
      open += 1
    }
    guard let close = matching(open: "[", close: "]", from: open, end: end),
      close + 1 < end, chars[close + 1] == "(",
      let paren = matching(open: "(", close: ")", from: close + 1, end: end)
    else { return nil }
    var destination = String(chars[close + 2..<paren]).trimmingSpaces()
    if destination.first == "<", let gt = destination.firstIndex(of: ">") {
      destination = String(destination[destination.index(after: destination.startIndex)..<gt])
    } else if let space = destination.firstIndex(where: \.isWhitespace) {
      destination = String(destination[..<space])  // drops a title
    }
    let text = parse(open + 1..<close, depth: depth + 1)
    return (.link(text, destination: destination), paren + 1)
  }

  /// The index of the bracket closing the one at `from`, skipping escapes and code spans.
  private func matching(open: Character, close: Character, from: Int, end: Int) -> Int? {
    var depth = 0
    var j = from
    let limit = min(end, from + Self.maxSpan)
    while j < limit {
      switch chars[j] {
      case "\\":
        j += 2
        continue
      case "`":
        let count = run(at: j, end: end)
        j = codeClose(from: j + count, count: count, end: end).map { $0 + count } ?? j + count
        continue
      case open: depth += 1
      case close:
        depth -= 1
        if depth == 0 { return j }
      default: break
      }
      j += 1
    }
    return nil
  }

  /// `<https://…>` or `<user@host>`.
  private func autolink(at i: Int, end: Int) -> (MarkdownInline, Int)? {
    var j = i + 1
    let limit = min(end, i + 1 + Self.maxSpan)
    while j < limit, chars[j] != ">", chars[j] != "<", !chars[j].isWhitespace { j += 1 }
    guard j < end, chars[j] == ">", j > i + 1 else { return nil }
    let target = String(chars[i + 1..<j])
    if target.contains("://") {
      return (.link([.text(target)], destination: target), j + 1)
    }
    if target.contains("@"), !target.hasPrefix("@"), !target.hasSuffix("@") {
      return (.link([.text(target)], destination: "mailto:" + target), j + 1)
    }
    return nil
  }

  // MARK: Helpers

  private func run(at i: Int, end: Int) -> Int {
    var j = i
    while j < end, chars[j] == chars[i] { j += 1 }
    return j - i
  }

  /// Collects inlines, merging adjacent text.
  private struct Output {
    var inlines: [MarkdownInline] = []
    var text = ""

    mutating func append(_ character: Character) { text.append(character) }
    mutating func append(_ string: String) { text += string }

    mutating func append(_ inline: MarkdownInline) {
      flush()
      inlines.append(inline)
    }

    /// Removes trailing spaces from the pending text; returns how many.
    mutating func trimTrailingSpaces() -> Int {
      var count = 0
      while text.last == " " {
        text.removeLast()
        count += 1
      }
      return count
    }

    mutating func flush() {
      if !text.isEmpty { inlines.append(.text(text)) }
      text = ""
    }

    mutating func finish() -> [MarkdownInline] {
      flush()
      return inlines
    }
  }
}

extension Character {
  fileprivate var isASCIIPunctuation: Bool {
    isASCII && (isPunctuation || isSymbol)
  }

  fileprivate var isLetterOrDigit: Bool { isLetter || isNumber }
}
