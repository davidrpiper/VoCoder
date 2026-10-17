import Testing
import VoCoderUIBridge

@Suite struct NodeRenderingTests {
  @Test func textAndContainers() {
    #expect(render(.text("hello")) == lines("hello"))
    #expect(
      render(.vbox([.text("a"), .separator(), .text("b")]), width: 4) == lines("a", "────", "b"))
    #expect(render(.hbox([.text("a"), .filler(), .text("b")]), width: 5) == lines("a   b"))
    #expect(render(.dbox([.text("aaaa"), .text("b")])) == lines("baaa"))
  }

  @Test func clearUnderHidesWhatIsBelow() {
    let below = VCNode.text("aaaa")
    // The popup's box is 3 cells wide but its text paints only one. (Size constraints only act
    // inside a container.)
    let box = VCNode.hbox([.text("b"), .filler()]).width(.equal, 3)
    #expect(render(.dbox([below, .hbox([box, .filler()])])) == lines("baaa"))
    #expect(render(.dbox([below, .hbox([box.clearUnder(), .filler()])])) == lines("b  a"))
  }

  @Test func paragraphWrapsToWidth() {
    let text = "the quick brown fox jumps over the lazy dog"
    #expect(
      render(.paragraph(text), width: 12)
        == lines("the quick", "brown fox", "jumps over", "the lazy dog"))
  }

  @Test func gaugeAndSpinner() {
    #expect(render(.gauge(0.5, axis: .horizontal), width: 10) == lines("█████"))
    #expect(render(.gauge(1.5, axis: .horizontal), width: 4) == lines("████"))  // clamped
    #expect(
      render(VCNode.gauge(0.5, axis: .vertical).height(.equal, 4), width: 1)
        == lines("", "", "█", "█"))
    #expect(render(.spinner(charset: 5, frame: 1)) == lines("↖"))
  }

  @Test func tableWithHeaderAndBorder() {
    let table = VCNode.table(
      [[.text("Name"), .text("Age")], [.text("Ann"), .text("31")], [.text("Bob")]],
      options: [.header, .border])
    #expect(
      render(table)
        == lines(
          "┌────────┐",
          "│Name Age│",
          "├────────┤",
          "│Ann  31 │",
          "│Bob     │",
          "└────────┘"))
  }

  @Test func tableWithSeparators() {
    let table = VCNode.table(
      [[.text("a"), .text("b")], [.text("cc"), .text("d")]],
      options: [.columnSeparators, .rowSeparators])
    #expect(render(table) == lines("a │b", "──┼─", "cc│d"))
    #expect(render(.table([], options: .border)) == lines(""))
  }

  @Test func tabBarHighlightsSelection() {
    let bar = VCNode.tabBar(["One", "Two"], selected: 1)
    #expect(render(bar) == lines(" One  Two"))
    let renderer = VCRenderer()
    renderer.setRoot(bar)
    let ansi = renderer.renderToString(width: 10, height: 1, ansi: true)
    #expect(ansi.contains("\u{1B}[1m\u{1B}[7m Two") || ansi.contains("\u{1B}[7m\u{1B}[1m Two"))
  }

  @Test func borders() {
    #expect(render(VCNode.text("x").bordered(), width: 3) == lines("┌─┐", "│x│", "└─┘"))
    #expect(
      render(VCNode.text("content").bordered(style: .rounded, title: "T"), width: 9)
        == lines("╭T──────╮", "│content│", "╰───────╯"))
    #expect(
      render(VCNode.text("x").bordered(style: .double, title: nil), width: 3)
        == lines("╔═╗", "║x║", "╚═╝"))
  }

  @Test func sizeAndAlignment() {
    // Size constraints act inside containers; the root always gets the whole screen.
    let centered = VCNode.text("x").aligned(.center).width(.equal, 5).height(.equal, 3)
    #expect(render(.hbox([centered, .text("|")])) == lines("     |", "  x", ""))
    #expect(
      render(.hbox([VCNode.text("abcdef").width(.lessThan, 3), .text("|")])) == lines("abc|"))
    #expect(
      render(.hbox([VCNode.text("a").flex(.horizontal), .text("|")]), width: 5) == lines("a   |"))
  }

  @Test func modifiersApplyInOrder() {
    // Styling then bordering styles the content only; bordering then styling styles both.
    let inner = VCRenderer()
    inner.setRoot(VCNode.text("x").foreground(.named(.red)).bordered())
    let innerANSI = inner.renderToString(width: 3, height: 3, ansi: true)
    let outer = VCRenderer()
    outer.setRoot(VCNode.text("x").bordered().foreground(.named(.red)))
    let outerANSI = outer.renderToString(width: 3, height: 3, ansi: true)
    // "\r\n" is a single Character in Swift.
    let firstLine = { (s: String) in String(s.split(separator: "\r\n").first ?? "") }
    #expect(!firstLine(innerANSI).contains("[31m"))
    #expect(firstLine(outerANSI).contains("[31m"))
  }

  @Test func colorsAndStylesInANSI() {
    let renderer = VCRenderer()
    renderer.setRoot(
      .hbox([
        VCNode.text("a").foreground(.named(.red)),
        VCNode.text("b").foreground(.palette256(208)),
        VCNode.text("c").background(.rgb(1, 2, 3)),
        VCNode.text("d").styled([.bold, .underlined]),
      ]))
    let ansi = renderer.renderToString(width: 4, height: 1, ansi: true)
    #expect(ansi.contains("[31m"))
    #expect(ansi.contains("[38;5;208m"))
    #expect(ansi.contains("[48;2;1;2;3m"))
    #expect(ansi.contains("[1m") && ansi.contains("[4m"))
  }

  @Test func coloredBorderLeavesContentDefault() {
    let renderer = VCRenderer()
    renderer.setRoot(
      .hbox([
        VCNode.text("x").bordered(style: .rounded, title: "T", color: .named(.red)),
        VCNode.text("y").foreground(.named(.green)).bordered(
          style: .light, title: nil, color: .named(.blue)),
      ]))
    #expect(
      renderer.renderToString(width: 6, height: 3, ansi: false)
        == lines("╭T╮┌─┐", "│x││y│", "╰─╯└─┘"))
    let rows = renderer.renderToString(width: 6, height: 3, ansi: true).split(separator: "\r\n")
    #expect(rows[0].contains("[31m") && rows[0].contains("[34m"))
    // Middle row: the border colour stops before the content; content keeps its own colour.
    #expect(rows[1].contains("│\u{1B}[39m\u{1B}[49mx") && rows[1].contains("[32m\u{1B}[49my"))
    let long = VCRenderer()
    long.setRoot(VCNode.text("x").bordered(style: .light, title: "Long title", color: .named(.red)))
    #expect(
      long.renderToString(width: 6, height: 3, ansi: false) == lines("┌Long┐", "│x   │", "└────┘"))
  }

  @Test func colorDepthDegradesColors() {
    let renderer = VCRenderer()
    renderer.setRoot(VCNode.text("a").foreground(.rgb(255, 135, 0)))
    let truecolor = renderer.renderToString(width: 1, height: 1, colorDepth: .trueColor)
    let palette256 = renderer.renderToString(width: 1, height: 1, colorDepth: .palette256)
    let palette16 = renderer.renderToString(width: 1, height: 1, colorDepth: .palette16)
    #expect(truecolor.contains("[38;2;255;135;0m"))
    #expect(palette256.contains("[38;5;208m"))
    #expect(!palette16.contains("[38;"))
    // The process-wide setting is restored afterwards.
    let before = VCRenderer.colorDepth
    _ = renderer.renderToString(width: 1, height: 1, colorDepth: .monochrome)
    #expect(VCRenderer.colorDepth == before)
  }

  @Test func wideCharacters() {
    #expect(render(.text("café 日本 x")) == lines("café 日本 x"))
    #expect(render(.hbox([.text("日本"), .text("|")])) == lines("日本|"))
  }

  @Test func plainTextMatchesANSIWithoutEscapes() {
    let renderer = VCRenderer()
    renderer.setRoot(
      .vbox([
        .tabBar(["Home", "Repo"], selected: 0),
        .separator(),
        VCNode.text("日本 café").foreground(.named(.cyan)),
        VCNode.table([[.text("k"), .text("v")]], options: .border),
        .gauge(0.3, axis: .horizontal),
      ]))
    let plain = renderer.renderToString(width: 16, height: 8, ansi: false)
    let ansi = renderer.renderToString(width: 16, height: 8, ansi: true)
    #expect(stripANSI(ansi) + "\n" == plain)
  }

  @Test func renderIsStable() {
    let renderer = VCRenderer()
    renderer.setRoot(
      .vbox([
        .text("a"), .input(id: "i", placeholder: "p", multiline: false),
        .menu(id: "m", entries: ["x"]),
      ]))
    let first = renderer.renderToString(width: 10, height: 5, ansi: true)
    #expect(renderer.renderToString(width: 10, height: 5, ansi: true) == first)
  }

  @Test func fitHeightUsesContent() {
    #expect(render(.vbox([.text("a"), .text("b")])) == lines("a", "b"))
    #expect(render(.vbox([])) == lines(""))
  }
}
