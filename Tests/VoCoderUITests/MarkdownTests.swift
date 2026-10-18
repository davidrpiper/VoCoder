import Testing
import VoCoderUI
import VoCoderUIBridge
import VoCoderUITestSupport

/// Each construct at two widths (plain) and in both themes (ANSI).
@MainActor
private func assertConstruct(
  _ source: String, filePath: String = #filePath, function: String = #function,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let view = Markdown(source)
  for width in [40, 80] {
    assertSnapshot(
      of: view, width: width, named: "w\(width)", filePath: filePath, function: function,
      sourceLocation: sourceLocation)
  }
  for theme in [Theme.dark, .light] {
    assertSnapshot(
      of: view, width: 40, theme: theme, format: .ansi(), named: theme.name, filePath: filePath,
      function: function, sourceLocation: sourceLocation)
  }
}

@MainActor @Suite struct MarkdownSnapshotTests {
  @Test func headings() {
    assertConstruct(
      """
      # Release notes for the next version
      Intro text.
      ## Fixes
      ### Details, *styled* and `coded`
      Setext title
      ------------
      """)
  }

  @Test func styledParagraphs() {
    assertConstruct(
      """
      The **agent** finished *all* of the ~~three~~ tasks: it ran `make test`, fixed the \
      **flaky _snapshot_ test** and updated `docs/PROGRESS.md` (see [the plan](docs/PLAN.md)).
      Second line of the same paragraph.

      A hard break follows
      this line, and <https://example.com/a/very/long/path/that/does/not/fit/in/forty/columns>.
      """)
  }

  @Test func codeBlocks() {
    assertConstruct(
      """
      Run this:

      ```swift
      let renderer = VCRenderer()  // a line that is longer than forty columns and never wraps
          indented()

      done()
      ```

      ```
      ```
      """)
  }

  @Test func lists() {
    assertConstruct(
      """
      - first item that is long enough to wrap onto a second line at forty columns
      - second with **bold** and `code`
        - nested one
          - nested two
            - nested three
      - third

      8. eight
      9. nine, with a continuation
         line
      10. ten
          ```
          code in an item
          ```
      """)
  }

  @Test func quotesAndRules() {
    assertConstruct(
      """
      > Quoted text that goes on for long enough to wrap inside the quote bar.
      >
      > - a list in a quote
      > > nested quote

      ---

      after the rule
      """)
  }

  @Test func tables() {
    assertConstruct(
      """
      | File | Status |
      |------|:------:|
      | `Sources/VoCoderUI/Views/Markdown.swift` | added |
      """)
  }

  @Test func malformedInput() {
    assertConstruct(
      """
      **never closed and *also not, `open code, [open link](, a_b_c, 2 * 3 * 4

      ```python
      unclosed fence
      # not a heading
      """)
  }

  @Test func agentReply() {
    assertConstruct(
      """
      I fixed the failing test. The problem was in `GitParsers.swift`:

      1. **Quoted paths** weren't unescaped, so `"a b.txt"` kept its quotes.
      2. The rename score was parsed as the path.

      ```diff
      - let path = fields[8]
      + let path = unquote(fields[9])
      ```

      > Note: run `make test` again before committing.
      """)
  }
}

@MainActor @Suite struct MarkdownLayoutTests {
  @Test func styledTextWraps() {
    let text = "aaa **bbb ccc** *ddd* `eee fff` ggg"
    #expect(render(Markdown(text), width: 10) == lines("aaa bbb", "ccc ddd", "eee fff", "ggg"))
  }

  @Test func punctuationStaysWithStyledWords() {
    #expect(render(Markdown("x **bold**, `y`."), width: 6) == lines("x", "bold,", "y."))
  }

  @Test func longWordsBreakInsteadOfClipping() {
    #expect(render(Markdown("see abcdefghijkl"), width: 5) == lines("see", "abcde", "fghij", "kl"))
  }

  @Test func codeBlocksDoNotWrap() {
    #expect(render(Markdown("```\nabc def ghi\n```"), width: 6) == lines(" abc d"))
  }

  @Test func listItemsHangIndent() {
    #expect(
      render(Markdown("- aaa bbb ccc\n  - ddd eee"), width: 10)
        == lines("• aaa bbb", "  ccc", "  ◦ ddd", "    eee"))
  }

  @Test func blocksAreSeparatedByABlankLine() {
    #expect(
      render(Markdown("# T\npara\n- a\n- b"), width: 10) == lines("T", "", "para", "", "• a", "• b")
    )
  }

  @Test func emptyDocumentRendersNothing() {
    #expect(render(Markdown(""), width: 5) == lines(""))
  }

  @Test func flowViewWraps() {
    let view = Flow {
      Text("one").bold()
      Text("two")
      HStack {
        Text("thr")
        Text("ee").italic()
      }
    }
    #expect(render(view, width: 8) == lines("one two", "three"))
  }
}
