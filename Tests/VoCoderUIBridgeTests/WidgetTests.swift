import Testing
import VoCoderUIBridge

@Suite struct InputWidgetTests {
  let renderer = VCRenderer()

  func tree(_ label: String) -> VCNode {
    .vbox([.text(label), .input(id: "name", placeholder: "type here", multiline: false)])
  }

  @Test func placeholderThenValue() {
    renderer.setRoot(tree("A"))
    #expect(renderer.renderToString(width: 12, height: 0, ansi: false) == lines("A", "type here"))
    renderer.setStringValue("Ada", forWidget: "name")
    #expect(renderer.renderToString(width: 12, height: 0, ansi: false) == lines("A", "Ada"))
    #expect(renderer.stringValue(forWidget: "name") == "Ada")
    #expect(renderer.integerValue(forWidget: "name") == 3)  // cursor at end
  }

  @Test func valueSetBeforeFirstRenderIsKept() {
    renderer.setStringValue("early", forWidget: "name")
    renderer.setRoot(tree("A"))
    #expect(renderer.renderToString(width: 12, height: 0, ansi: false) == lines("A", "early"))
  }

  @Test func stateSurvivesTreeSwaps() {
    renderer.setRoot(tree("A"))
    _ = renderer.renderToString(width: 12, height: 2, ansi: false)
    renderer.focusedWidget = "name"
    renderer.injectInput("hi")
    renderer.setRoot(tree("B"))
    renderer.setRoot(.vbox([.text("other tree")]))  // widget not in this tree
    renderer.setRoot(tree("C"))
    #expect(renderer.renderToString(width: 12, height: 0, ansi: false) == lines("C", "hi"))
    #expect(renderer.stringValue(forWidget: "name") == "hi")
  }

  @Test func typingReportsChangesNotKeys() {
    let recorder = EventRecorder(renderer)
    renderer.setRoot(tree("A"))
    _ = renderer.renderToString(width: 12, height: 2, ansi: false)
    renderer.focusedWidget = "name"
    renderer.injectInput("hé")
    let changes = recorder.events.filter { $0.kind == .widgetChanged }
    #expect(changes.map(\.stringValue) == ["h", "hé"])
    #expect(changes.allSatisfy { $0.widgetId == "name" })
    #expect(recorder.keys.isEmpty)
    renderer.injectInput("\u{7F}")  // Backspace
    #expect(recorder.events.last?.stringValue == "h")
  }

  @Test func enterSubmitsSingleLine() {
    let recorder = EventRecorder(renderer)
    renderer.setRoot(tree("A"))
    renderer.focusedWidget = "name"
    renderer.injectInput("ok\r")
    let submitted = recorder.events.last
    #expect(submitted?.kind == .widgetSubmitted)
    #expect(submitted?.stringValue == "ok")
    #expect(renderer.stringValue(forWidget: "name") == "ok")
  }

  @Test func enterInsertsNewlineInMultiline() {
    let recorder = EventRecorder(renderer)
    renderer.setRoot(.input(id: "body", placeholder: "", multiline: true))
    renderer.focusedWidget = "body"
    renderer.injectInput("a\rb")
    #expect(renderer.stringValue(forWidget: "body") == "a\nb")
    #expect(!recorder.events.contains { $0.kind == .widgetSubmitted })
    #expect(renderer.renderToString(width: 5, height: 0, ansi: false) == lines("a", "b"))
  }

  @Test func commandKeysBypassFocusedInput() {
    let recorder = EventRecorder(renderer)
    renderer.setRoot(tree("A"))
    renderer.focusedWidget = "name"
    renderer.injectInput("\u{1B}")  // Esc
    renderer.injectInput("\t\u{1B}[Z\u{3}\u{0}")  // Tab, Shift-Tab, Ctrl-C, Ctrl-Space
    #expect(recorder.keys == ["Esc", "Tab", "Shift-Tab", "Ctrl-c", "Ctrl-Space"])
    #expect(renderer.stringValue(forWidget: "name") == "")
  }

  @Test func unconsumedKeysReachSwift() {
    let recorder = EventRecorder(renderer)
    renderer.setRoot(tree("A"))
    renderer.focusedWidget = "name"
    renderer.injectInput("\u{1B}[15~")  // F5: the input ignores it
    #expect(recorder.keys == ["F5"])
  }

  @Test func unfocusedInputGetsNothing() {
    let recorder = EventRecorder(renderer)
    renderer.setRoot(tree("A"))
    renderer.injectInput("q")
    #expect(recorder.keys == ["q"])
    #expect(renderer.stringValue(forWidget: "name") == "")
  }

  @Test func cursorCanBeSet() {
    renderer.setRoot(tree("A"))
    renderer.setStringValue("abc", forWidget: "name")
    renderer.setIntegerValue(1, forWidget: "name")
    renderer.focusedWidget = "name"
    renderer.injectInput("X")
    #expect(renderer.stringValue(forWidget: "name") == "aXbc")
    renderer.setIntegerValue(99, forWidget: "name")
    #expect(renderer.integerValue(forWidget: "name") == 4)
  }
}

@Suite struct MenuWidgetTests {
  let renderer = VCRenderer()

  @Test func arrowsChangeSelectionAndEnterSubmits() {
    let recorder = EventRecorder(renderer)
    renderer.setRoot(.menu(id: "m", entries: ["a", "b", "c"]))
    #expect(renderer.renderToString(width: 5, height: 0, ansi: false) == lines("> a", "  b", "  c"))
    renderer.focusedWidget = "m"
    renderer.injectInput("\u{1B}[B\u{1B}[B")
    #expect(renderer.integerValue(forWidget: "m") == 2)
    #expect(recorder.events.filter { $0.kind == .widgetChanged }.map(\.integerValue) == [1, 2])
    renderer.injectInput("\r")
    #expect(recorder.events.last?.kind == .widgetSubmitted)
    #expect(recorder.events.last?.integerValue == 2)
    #expect(recorder.events.last?.stringValue == nil)
    #expect(renderer.renderToString(width: 5, height: 0, ansi: false) == lines("  a", "  b", "> c"))
  }

  @Test func selectionClampedWhenEntriesShrink() {
    renderer.setRoot(.menu(id: "m", entries: ["a", "b", "c"]))
    renderer.setIntegerValue(2, forWidget: "m")
    renderer.setRoot(.menu(id: "m", entries: ["a"]))
    _ = renderer.renderToString(width: 5, height: 0, ansi: false)
    #expect(renderer.integerValue(forWidget: "m") == 0)
  }

  @Test func selectionSetBeforeFirstRender() {
    renderer.setIntegerValue(1, forWidget: "m")
    renderer.setRoot(.menu(id: "m", entries: ["a", "b"]))
    #expect(renderer.renderToString(width: 5, height: 0, ansi: false) == lines("  a", "> b"))
  }
}

@Suite struct ScrollFrameTests {
  let renderer = VCRenderer()

  func rows(_ count: Int, marked: Int? = nil) -> VCNode {
    .vbox(
      (0..<count).map { i in
        let row = VCNode.text("row \(i)")
        return i == marked ? row.focusMarker() : row
      })
  }

  func frame(_ child: VCNode, follow: Bool = false) -> VCNode {
    .vbox([.text("hdr"), .scrollFrame(id: "s", followingEnd: follow, child: child), .text("ftr")])
  }

  @Test func storedOffsetIsUsedAndPersists() {
    renderer.setRoot(frame(rows(10)))
    #expect(
      renderer.renderToString(width: 8, height: 5, ansi: false)
        == lines("hdr", "row 0", "row 1", "row 2", "ftr"))
    renderer.setIntegerValue(4, forWidget: "s")
    renderer.setRoot(frame(rows(10)))
    #expect(
      renderer.renderToString(width: 8, height: 5, ansi: false)
        == lines("hdr", "row 4", "row 5", "row 6", "ftr"))
  }

  @Test func offsetIsClampedAndWrittenBack() {
    renderer.setRoot(frame(rows(10)))
    renderer.setIntegerValue(50, forWidget: "s")
    #expect(
      renderer.renderToString(width: 8, height: 5, ansi: false)
        == lines("hdr", "row 7", "row 8", "row 9", "ftr"))
    #expect(renderer.integerValue(forWidget: "s") == 7)
  }

  @Test func focusMarkerScrollsMinimally() {
    renderer.setRoot(frame(rows(10, marked: 5)))
    #expect(
      renderer.renderToString(width: 8, height: 5, ansi: false)
        == lines("hdr", "row 3", "row 4", "row 5", "ftr"))
    // Moving the marker up within the view doesn't scroll.
    renderer.setRoot(frame(rows(10, marked: 4)))
    #expect(
      renderer.renderToString(width: 8, height: 5, ansi: false)
        == lines("hdr", "row 3", "row 4", "row 5", "ftr"))
    renderer.setRoot(frame(rows(10, marked: 1)))
    #expect(
      renderer.renderToString(width: 8, height: 5, ansi: false)
        == lines("hdr", "row 1", "row 2", "row 3", "ftr"))
  }

  @Test func followingEndPinsToBottom() {
    renderer.setRoot(frame(rows(10), follow: true))
    #expect(
      renderer.renderToString(width: 8, height: 5, ansi: false)
        == lines("hdr", "row 7", "row 8", "row 9", "ftr"))
    renderer.setRoot(frame(rows(12), follow: true))
    #expect(
      renderer.renderToString(width: 8, height: 5, ansi: false)
        == lines("hdr", "row 9", "row 10", "row 11", "ftr"))
    // Stop following: the view stays where it was.
    renderer.setRoot(frame(rows(20)))
    #expect(renderer.renderToString(width: 8, height: 5, ansi: false).contains("row 9\n"))
  }

  @Test func shortContentDoesNotScroll() {
    renderer.setRoot(frame(rows(2), follow: true))
    #expect(
      renderer.renderToString(width: 8, height: 5, ansi: false)
        == lines("hdr", "row 0", "row 1", "ftr", ""))
    #expect(renderer.integerValue(forWidget: "s") == 0)
  }
}

@Suite struct WidgetRegistryTests {
  let renderer = VCRenderer()

  @Test func unknownWidgets() {
    #expect(renderer.stringValue(forWidget: "nope") == nil)
    #expect(renderer.integerValue(forWidget: "nope") == VCNoValue)
    #expect(renderer.widgetIds.isEmpty)
  }

  @Test func removeDropsState() {
    renderer.setRoot(.input(id: "a", placeholder: "", multiline: false))
    renderer.setStringValue("x", forWidget: "a")
    #expect(renderer.widgetIds == ["a"])
    renderer.removeWidget("a")
    #expect(renderer.widgetIds.isEmpty)
    #expect(renderer.renderToString(width: 5, height: 1, ansi: false) == lines(""))
  }

  @Test func idReusedForAnotherKindStartsFresh() {
    renderer.setRoot(.input(id: "w", placeholder: "", multiline: false))
    renderer.setStringValue("text", forWidget: "w")
    _ = renderer.renderToString(width: 5, height: 1, ansi: false)
    renderer.setRoot(.menu(id: "w", entries: ["a", "b"]))
    _ = renderer.renderToString(width: 5, height: 0, ansi: false)
    #expect(renderer.stringValue(forWidget: "w") == nil)
    #expect(renderer.integerValue(forWidget: "w") == 0)
  }
}
