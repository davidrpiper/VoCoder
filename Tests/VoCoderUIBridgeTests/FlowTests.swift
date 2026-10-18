import Testing
import VoCoderUIBridge

@Suite struct FlowTests {
  let words = "the quick brown fox jumps".split(separator: " ").map { VCNode.text(String($0)) }

  @Test func wrapsWordsToTheWidth() {
    #expect(render(.flow(words), width: 10) == lines("the quick", "brown fox", "jumps"))
    #expect(render(.flow(words), width: 40) == lines("the quick brown fox jumps"))
    #expect(render(.flow([]), width: 10) == lines(""))
  }

  @Test func wrapsInsideContainers() {
    #expect(
      render(.vbox([.flow(words), .text("end")]).bordered(), width: 12)
        == lines(
          "┌──────────┐",
          "│the quick │",
          "│brown fox │",
          "│jumps     │",
          "│end       │",
          "└──────────┘"))
    // In an hbox the flow takes the rest of the row, so a marker gets a hanging indent.
    #expect(
      render(.hbox([.text("- "), .flow(words)]), width: 12)
        == lines("- the quick", "  brown fox", "  jumps"))
    #expect(
      render(.hbox([.text("- "), .flow(words), .text("|")]), width: 30)
        == lines("- the quick brown fox jumps  |"))
  }

  @Test func breaksAWordWiderThanTheLine() {
    let flow = VCNode.flow([.text("ab"), .text("abcdefghijklmnop"), .text("cd")])
    #expect(render(flow, width: 6) == lines("ab", "abcdef", "ghijkl", "mnop", "cd"))
    #expect(
      render(.vbox([.flow([.text("abcdefghij")]), .text("end")]), width: 4)
        == lines("abcd", "efgh", "ij", "end"))
  }

  @Test func keepsEachWordsStyles() {
    // One word mixing styles: bold "bold" directly followed by a plain comma.
    let word = VCNode.hbox([VCNode.text("bold").styled(.bold), .text(",")])
    let flow = VCNode.flow([.text("a"), word, .text("b")])
    #expect(render(flow, width: 6) == lines("a", "bold,", "b"))
    let renderer = VCRenderer()
    renderer.setRoot(flow)
    let ansi = renderer.renderToString(width: 20, height: 1, ansi: true)
    #expect(ansi.contains("\u{1B}[1mbold\u{1B}[22m,"))
    // A broken word keeps its style on every slice.
    renderer.setRoot(.flow([VCNode.text("abcdef").styled(.bold)]))
    let broken = renderer.renderToString(width: 3, height: 2, ansi: true)
    #expect(broken.contains("\u{1B}[1mabc") && broken.contains("\u{1B}[1mdef"))
  }
}
