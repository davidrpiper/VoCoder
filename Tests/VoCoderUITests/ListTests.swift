import Observation
import Testing
import VoCoderUI
import VoCoderUITestSupport

private struct SampleIssue {
  let key: String
  let title: String
  let status: String
}

private let issues = (1...30).map {
  SampleIssue(
    key: "ENG-\(100 + $0)", title: "Task number \($0)", status: $0 % 3 == 0 ? "Done" : "Todo")
}

@MainActor
@Suite struct ListStateTests {
  @Test func movementClampsToItems() {
    let state = ListState(pageSize: 5)
    #expect(state.perform(.moveUp, count: 10))
    #expect(state.selection == 0)
    state.perform(.pageDown, count: 10)
    #expect(state.selection == 5)
    state.perform(.pageDown, count: 10)
    #expect(state.selection == 9)
    state.perform(.moveToFirst, count: 10)
    #expect(state.selection == 0)
    state.perform(.moveToLast, count: 10)
    #expect(state.selection == 9)
    #expect(!state.perform(.activate, count: 10))
    #expect(!state.perform(.moveLeft, count: 10))
  }

  @Test func staleSelectionIsClamped() {
    let state = ListState(selection: 8)
    #expect(state.selectedIndex(count: 3) == 2)
    #expect(state.selectedIndex(count: 0) == nil)
    state.perform(.moveUp, count: 3)
    #expect(state.selection == 1)
    state.perform(.moveDown, count: 0)
    #expect(state.selection == 0)
  }
}

@MainActor
@Suite struct ListViewTests {
  let state = ListState(selection: 20)

  func list(focused: Bool) -> some View {
    VStack {
      ListView("issues", state: state, items: issues) { issue, row in
        HStack {
          Text(row.isSelected ? "›" : " ")
          Text(issue.key).foreground(.accent)
          Text(" " + issue.title)
        }
      }
      .border(.rounded, title: "Issues", color: focused ? .focus : .border)
      .flex()
      if !focused { Focusable("elsewhere") { _ in Text("other pane") } }
    }
  }

  @Test func selectedRowScrolledIntoView() {
    assertSnapshot(of: list(focused: true), width: 30, height: 8, focus: "issues")
  }

  @Test func focusedAndUnfocusedSelectionColors() {
    assertSnapshot(
      of: list(focused: true), width: 30, height: 8, focus: "issues", format: .ansi(),
      named: "focused")
    assertSnapshot(
      of: list(focused: false), width: 30, height: 9, focus: "elsewhere", format: .ansi(),
      named: "unfocused")
  }

  @Test func emptyList() {
    let view = ListView("empty", state: state, items: [String](), emptyText: "No issues") {
      item, _ in Text(item)
    }
    #expect(render(view, width: 12) == lines("No issues"))
  }

  @Test func tableKeepsHeaderAndAlignsColumns() {
    let table = TableView(
      "table", state: ListState(selection: 4), items: issues,
      columns: [
        TableColumn("Key", width: .fixed(7)) { $0.key },
        TableColumn("Title", width: .flexible) { $0.title },
        TableColumn("Status", width: .fixed(6)) { $0.status },
      ])
    assertSnapshot(of: table.border(.light), width: 36, height: 8, focus: "table")
    assertSnapshot(
      of: table.border(.light), width: 36, height: 8, focus: "table", format: .ansi(),
      named: "colors")
  }
}

@MainActor
@Suite struct ScrollViewTests {
  @Test func focusableScrollViewScrollsAndFollowsTheEnd() {
    let state = ScrollState(followsEnd: true, pageSize: 3)
    let host = UIHost(theme: .dark) {
      ScrollView("log", state: state) {
        for line in 1...20 { Text("line \(line)") }
      }
    }
    #expect(host.plain(width: 10, height: 3) == lines("line 18", "line 19", "line 20"))
    host.perform(.pageUp)
    #expect(!state.followsEnd)
    #expect(host.plain(width: 10, height: 3) == lines("line 15", "line 16", "line 17"))
    host.perform(.moveToFirst)
    host.perform(.moveDown)
    #expect(host.plain(width: 10, height: 3) == lines("line 2", "line 3", "line 4"))
    host.perform(.moveToLast)
    #expect(state.followsEnd)
    #expect(host.plain(width: 10, height: 3) == lines("line 18", "line 19", "line 20"))
  }
}

@MainActor
@Observable
private final class Counter {
  var value = 0
  var unread = 0
}

@MainActor
@Suite struct HostTests {
  @Test func observedChangesInvalidateOnlyWhenRead() async {
    let counter = Counter()
    let host = UIHost(theme: .dark) { Text("count \(counter.value)") }
    host.render()
    #expect(!host.needsRender)
    counter.unread += 1  // not read by the view
    await Task.yield()
    #expect(!host.needsRender)
    counter.value = 5
    // onChange hops to the main queue; let it run.
    for _ in 0..<50 where !host.needsRender { await Task.yield() }
    #expect(host.needsRender)
    #expect(host.plain(width: 10) == lines("count 5"))
  }

  @Test func scheduledRendersCoalesce() async {
    let counter = Counter()
    let host = UIHost(theme: .dark) { Text("count \(counter.value)") }
    host.render()
    let before = host.renderCount
    for value in 1...10 { counter.value = value }
    host.invalidate()
    host.invalidate()
    for _ in 0..<100 where host.needsRender { await Task.yield() }
    #expect(host.renderCount == before + 1)
    #expect(host.plain(width: 10) == lines("count 10"))
  }
}
