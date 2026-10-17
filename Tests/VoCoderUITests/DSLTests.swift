import Testing
import VoCoderUI
import VoCoderUITestSupport

/// A composed view, as modules will write them.
private struct StatusPanel: View {
  let title: String
  let rows: [(String, String)]
  let busy: Bool

  var body: some View {
    VStack {
      HStack {
        Text(title).bold().foreground(.accent)
        Spacer()
        if busy {
          Spinner(frame: 3)
        } else {
          Text("✓").foreground(.success)
        }
      }
      Divider()
      for (key, value) in rows {
        HStack {
          Text(key).frame(width: .exactly(8)).foreground(.muted)
          Text(value)
        }
      }
      Gauge(0.4)
    }
    .border(.rounded, title: "status")
  }
}

@MainActor
@Suite struct DSLTests {
  @Test func stacksAndText() {
    #expect(
      render(
        VStack {
          Text("a")
          Text("b")
        }, width: 4) == lines("a", "b"))
    #expect(
      render(
        HStack {
          Text("a")
          Spacer()
          Text("b")
        }, width: 5) == lines("a   b"))
    #expect(
      render(
        ZStack {
          Text("aaaa")
          Text("b")
        }, width: 4) == lines("baaa"))
    #expect(render(EmptyView(), width: 4) == lines(""))
  }

  @Test func builderControlFlow() {
    func view(_ flag: Bool, _ count: Int, _ extra: String?) -> some View {
      VStack {
        if flag { Text("yes") } else { Text("no") }
        for index in 0..<count { Text("row \(index)") }
        if let extra { Text(extra) }
      }
    }
    #expect(render(view(true, 2, nil), width: 8) == lines("yes", "row 0", "row 1"))
    #expect(render(view(false, 0, "x"), width: 8) == lines("no", "x"))
  }

  @Test func bodyWithSeveralViewsStacksThem() {
    struct Pair: View {
      var body: some View {
        Text("one")
        Text("two")
      }
    }
    #expect(render(Pair().border(.light), width: 5) == lines("┌───┐", "│one│", "│two│", "└───┘"))
  }

  @Test func paragraphWraps() {
    #expect(
      render(Paragraph("the quick brown fox jumps"), width: 10)
        == lines("the quick", "brown fox", "jumps"))
  }

  @Test func framesAndFlex() {
    let view = HStack {
      Text("abcdef").frame(width: .exactly(3))
      Text("|")
      Text("x").flex(.horizontal)
      Text("|")
    }
    #expect(render(view, width: 8) == lines("abc|x  |"))
    #expect(render(Text("hi").centered(.horizontally), width: 6) == lines("  hi"))
  }

  @Test func gridTabBarAndDivider() {
    let grid = Grid([[Text("k"), Text("v")], [Text("key"), Text("value")]], header: true)
    #expect(render(grid, width: 12) == lines("k   v", "─────────", "key value"))
    #expect(render(TabBar(["A", "B"], selected: 0), width: 8) == lines(" A  B"))
    #expect(
      render(
        VStack {
          Text("a")
          Divider()
          Text("b")
        }, width: 3) == lines("a", "───", "b"))
  }

  @Test func panelSnapshot() {
    let panel = StatusPanel(
      title: "vocoder", rows: [("branch", "main"), ("changes", "3 files")], busy: false)
    assertSnapshot(of: panel, width: 30)
    assertSnapshot(of: panel, width: 30, format: .ansi(), named: "dark")
    assertSnapshot(of: panel, width: 30, theme: .light, format: .ansi(), named: "light")
    let busy = StatusPanel(title: "api-server", rows: [], busy: true)
    assertSnapshot(of: busy, width: 20, named: "busy")
  }

  @Test func coloredBorderKeepsContentColors() {
    let view = Text("x").foreground(.danger).border(.heavy, title: "T", color: .focus)
    assertSnapshot(of: view, width: 5, format: .ansi())
  }
}
