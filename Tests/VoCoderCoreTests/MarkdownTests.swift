import Testing
import VoCoderCore

private func blocks(_ source: String) -> [MarkdownBlock] {
  MarkdownDocument(parsing: source).blocks
}

private func inlines(_ source: String) -> [MarkdownInline] {
  guard case .paragraph(let inlines) = blocks(source).first else { return [] }
  return inlines
}

@Suite struct MarkdownBlockTests {
  @Test func headings() {
    #expect(blocks("# One") == [.heading(level: 1, [.text("One")])])
    #expect(blocks("### Three ###") == [.heading(level: 3, [.text("Three")])])
    #expect(blocks("## C# tips") == [.heading(level: 2, [.text("C# tips")])])
    #expect(blocks("#tag") == [.paragraph([.text("#tag")])])
    #expect(blocks("####### seven") == [.paragraph([.text("####### seven")])])
    #expect(blocks("Title\n=====") == [.heading(level: 1, [.text("Title")])])
    #expect(blocks("Title\n---") == [.heading(level: 2, [.text("Title")])])
  }

  @Test func paragraphsAndBreaks() {
    #expect(
      blocks("one\ntwo\n\nthree")
        == [.paragraph([.text("one"), .softBreak, .text("two")]), .paragraph([.text("three")])])
    #expect(blocks("a  \nb") == [.paragraph([.text("a"), .hardBreak, .text("b")])])
    #expect(blocks("a\\\nb") == [.paragraph([.text("a"), .hardBreak, .text("b")])])
    #expect(blocks("a\r\nb") == [.paragraph([.text("a"), .softBreak, .text("b")])])
    #expect(blocks("   indented") == [.paragraph([.text("indented")])])
  }

  @Test func fencedCode() {
    #expect(
      blocks("```swift\nlet a = 1\n  b\n```\nafter")
        == [.code(info: "swift", lines: ["let a = 1", "  b"]), .paragraph([.text("after")])])
    #expect(blocks("~~~\n```\n~~~") == [.code(info: "", lines: ["```"])])
    // Indented fence: content loses up to the fence's indentation.
    #expect(blocks("  ```\n    x\n y\n  ```") == [.code(info: "", lines: ["  x", "y"])])
    // Unclosed: runs to the end.
    #expect(blocks("```\n# not a heading\n") == [.code(info: "", lines: ["# not a heading", ""])])
    // Tabs expand to 4-column stops.
    #expect(blocks("```\n\tx\n```") == [.code(info: "", lines: ["    x"])])
    // Fences interrupt paragraphs.
    #expect(blocks("text\n```\ncode\n```").count == 2)
  }

  @Test func rulesAndQuotes() {
    #expect(blocks("***") == [.rule])
    #expect(blocks("- - -") == [.rule])
    #expect(blocks("a\n\n___\nb") == [.paragraph([.text("a")]), .rule, .paragraph([.text("b")])])
    #expect(
      blocks("> quoted\nlazy\n> # Head")
        == [
          .quote([
            .paragraph([.text("quoted"), .softBreak, .text("lazy")]),
            .heading(level: 1, [.text("Head")]),
          ])
        ])
    #expect(blocks("> > nested") == [.quote([.quote([.paragraph([.text("nested")])])])])
    #expect(blocks(">") == [.quote([])])
  }

  @Test func bulletLists() {
    #expect(
      blocks("- a\n- b\n* c")
        == [
          .list(
            MarkdownList(
              ordered: false,
              items: [
                [.paragraph([.text("a")])], [.paragraph([.text("b")])], [.paragraph([.text("c")])],
              ]))
        ])
    // Continuation lines, lazy lines and a blank line between items.
    #expect(
      blocks("- a\n  more\nlazy\n\n- b")
        == [
          .list(
            MarkdownList(
              ordered: false,
              items: [
                [.paragraph([.text("a"), .softBreak, .text("more"), .softBreak, .text("lazy")])],
                [.paragraph([.text("b")])],
              ]))
        ])
  }

  @Test func nestedLists() {
    let nested = MarkdownBlock.list(
      MarkdownList(ordered: false, items: [[.paragraph([.text("inner")])]]))
    #expect(
      blocks("- outer\n  - inner\n- next")
        == [
          .list(
            MarkdownList(
              ordered: false,
              items: [[.paragraph([.text("outer")]), nested], [.paragraph([.text("next")])]]))
        ])
    // "1. " content starts at column 3, but two spaces are enough (agents do this).
    #expect(
      blocks("1. outer\n  - inner")
        == [.list(MarkdownList(ordered: true, items: [[.paragraph([.text("outer")]), nested]]))])
    // Three levels.
    guard case .list(let top) = blocks("- a\n  - b\n    - c").first,
      case .list(let second) = top.items[0].last,
      case .list(let third) = second.items[0].last
    else {
      Issue.record("expected three nested lists")
      return
    }
    #expect(third.items == [[.paragraph([.text("c")])]])
  }

  @Test func orderedLists() {
    #expect(
      blocks("3. three\n4) four")
        == [
          .list(
            MarkdownList(
              ordered: true, start: 3,
              items: [[.paragraph([.text("three")])], [.paragraph([.text("four")])]]))
        ])
    // Only "1." interrupts a paragraph: a wrapped "2024. Then" stays text.
    #expect(
      blocks("since\n2024. Then") == [
        .paragraph([.text("since"), .softBreak, .text("2024. Then")])
      ])
    #expect(blocks("text\n- item").count == 2)
    // A list item holding a code block.
    #expect(
      blocks("1. run:\n   ```\n   make\n   ```")
        == [
          .list(
            MarkdownList(
              ordered: true,
              items: [[.paragraph([.text("run:")]), .code(info: "", lines: ["make"])]]))
        ])
  }

  @Test func pipeTablesStayAsLines() {
    #expect(
      blocks("Summary:\n| a | b |\n|---|:-:|\n| 1 | 2 |\n\nafter")
        == [
          .paragraph([.text("Summary:")]),
          .table(lines: ["| a | b |", "|---|:-:|", "| 1 | 2 |"]),
          .paragraph([.text("after")]),
        ])
    #expect(blocks("a | b") == [.paragraph([.text("a | b")])])
  }

  @Test func plainText() {
    let document = MarkdownDocument(
      parsing: "# Title\n\nSome **bold** and `code`.\n\n- [link](http://x)\n\n```\nls\n```")
    #expect(document.plainText == "Title\nSome bold and code.\nlink\nls")
  }
}

@Suite struct MarkdownInlineTests {
  @Test func emphasis() {
    #expect(inlines("**b**") == [.strong([.text("b")])])
    #expect(inlines("__b__") == [.strong([.text("b")])])
    #expect(inlines("a *i* b") == [.text("a "), .emphasis([.text("i")]), .text(" b")])
    #expect(inlines("_i_") == [.emphasis([.text("i")])])
    #expect(inlines("~~s~~") == [.strikethrough([.text("s")])])
    #expect(inlines("***x***") == [.strong([.emphasis([.text("x")])])])
    #expect(
      inlines("*a **b** c*")
        == [.emphasis([.text("a "), .strong([.text("b")]), .text(" c")])])
    #expect(inlines("**a\nb**") == [.strong([.text("a"), .softBreak, .text("b")])])
  }

  @Test func emphasisThatIsNot() {
    #expect(inlines("snake_case_name") == [.text("snake_case_name")])
    #expect(inlines("a * b * c") == [.text("a * b * c")])
    #expect(inlines("~one~") == [.text("~one~")])
    #expect(inlines("****b") == [.text("****b")])
  }

  @Test func unclosedEmphasisStaysLiteral() {
    #expect(inlines("**open") == [.text("**open")])
    #expect(inlines("*open") == [.text("*open")])
    #expect(inlines("**a*") == [.text("*"), .emphasis([.text("a")])])
    #expect(inlines("_x") == [.text("_x")])
  }

  @Test func codeSpans() {
    #expect(inlines("`a*b*`") == [.code("a*b*")])
    #expect(inlines("`` a`b ``") == [.code("a`b")])
    #expect(inlines("x `open") == [.text("x `open")])
    #expect(inlines("*a `*` b*") == [.emphasis([.text("a "), .code("*"), .text(" b")])])
    #expect(inlines("`a\nb`") == [.code("a b")])
  }

  @Test func links() {
    #expect(inlines("[text](http://x)") == [.link([.text("text")], destination: "http://x")])
    #expect(
      inlines("[**b**](u \"title\")") == [.link([.strong([.text("b")])], destination: "u")])
    #expect(inlines("![alt](img.png)") == [.link([.text("alt")], destination: "img.png")])
    #expect(inlines("[a](<with space>)") == [.link([.text("a")], destination: "with space")])
    #expect(inlines("[a](f(x))") == [.link([.text("a")], destination: "f(x)")])
    #expect(
      inlines("<https://a.b/c>") == [.link([.text("https://a.b/c")], destination: "https://a.b/c")])
    #expect(inlines("<me@x.io>") == [.link([.text("me@x.io")], destination: "mailto:me@x.io")])
    #expect(inlines("[ref][1] and [open") == [.text("[ref][1] and [open")])
    #expect(inlines("a < b > c") == [.text("a < b > c")])
    #expect(inlines("!bang") == [.text("!bang")])
  }

  @Test func escapes() {
    #expect(inlines("\\*not\\*") == [.text("*not*")])
    #expect(inlines("\\a") == [.text("\\a")])
    #expect(inlines("end\\") == [.text("end\\")])
  }
}

@Suite struct MarkdownRobustnessTests {
  /// Deterministic pseudo-random generator, so failures reproduce.
  struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E9B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  /// Markup-heavy noise: every parse terminates and keeps every letter. (Links are left out of
  /// the alphabet and digits aren't compared: destinations and list numbers are dropped by
  /// design.)
  @Test func randomMarkupNeverLosesText() {
    let pieces = [
      "*", "**", "_", "__", "~~", "`", "``", "```", "[", "]", "<", ">", "\\", "#", "# ", "- ",
      "1. ", "> ", "|", "---", "\n", "\n\n", "  ", "    ", "\t", "ab", "c", "12", " ", "é", "日本",
    ]
    var rng = SplitMix(state: 42)
    for _ in 0..<500 {
      let source = (0..<Int.random(in: 1...60, using: &rng)).map { _ in
        pieces.randomElement(using: &rng)!
      }.joined()
      let document = MarkdownDocument(parsing: source)
      let kept = document.plainText + infos(in: document.blocks).joined()
      #expect(letters(kept) == letters(source), "source: \(source.debugDescription)")
    }
  }

  @Test func pathologicalInputIsFast() {
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for source in [
        // Unclosed openers each scan at most `maxSpan` characters ahead.
        String(repeating: "*a ", count: 5_000), String(repeating: "[", count: 5_000),
        String(repeating: "``a", count: 20_000), String(repeating: "- ", count: 2_000),
        String(repeating: "> ", count: 2_000), String(repeating: "  - a\n", count: 2_000),
        String(repeating: "*_", count: 5_000) + "x" + String(repeating: "_*", count: 5_000),
      ] {
        _ = MarkdownDocument(parsing: source)
      }
    }
    #expect(elapsed < .seconds(10))
  }

  @Test func nestingIsCapped() {
    var blocks = MarkdownDocument(parsing: String(repeating: "> ", count: 100) + "deep").blocks
    var depth = 0
    while case .quote(let inner) = blocks.first {
      blocks = inner
      depth += 1
    }
    #expect(depth == 32)
    #expect(
      MarkdownDocument(parsing: String(repeating: "> ", count: 100) + "deep").plainText.hasSuffix(
        "deep"))
  }

  private func letters(_ text: String) -> [Character] {
    text.filter(\.isLetter).sorted()
  }

  private func infos(in blocks: [MarkdownBlock]) -> [String] {
    blocks.flatMap { block -> [String] in
      switch block {
      case .code(let info, _): [info]
      case .quote(let inner): infos(in: inner)
      case .list(let list): list.items.flatMap(infos)
      default: []
      }
    }
  }
}
