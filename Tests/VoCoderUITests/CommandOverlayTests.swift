import Observation
import Testing
import VoCoderCore
import VoCoderFakes
import VoCoderUI
import VoCoderUITestSupport

@MainActor
@Observable
final class Notes {
  var posted: [String] = []
  var counted: [Int] = []
  let list = ListState()
}

/// Something to draw the overlays over: a tab line, filler text and a focusable list.
struct Backdrop: View {
  let state: AppState
  let notes: Notes

  var body: some View {
    VStack {
      Text(
        "tabs: " + state.tabs.map(\.title).joined(separator: " | ")
          + " · selected: " + (state.selectedTab?.title ?? "-"))
      for row in 0..<8 {
        Text(String(repeating: "backdrop \(row) ", count: 8))
      }
      ListView("items", state: notes.list, items: ["one", "two", "three"]) { item, row in
        Text((row.isSelected ? "› " : "  ") + item)
      }
      .flex()
      Focusable("other") { focused in Text(focused ? "[other]" : " other ") }
    }
  }
}

/// The palette, which-key popup and help over a small app: tab commands, the UI built-ins and
/// a few test commands with parameters.
@MainActor
@Suite struct CommandOverlayTests {
  let state = AppState()
  let notes = Notes()
  let host = UIHost(theme: .dark)
  let keyboard: KeyboardController

  init() {
    for (id, title) in [("a", "alpha"), ("b", "beta"), ("c", "gamma")] {
      state.open(FakeTab(id: TabID(id), title: title))
    }
    let notes = notes
    let dispatcher = CommandDispatcher(state: state, registry: CommandRegistry(TabCommands.all))
    dispatcher.register([
      Command(
        id: "note.post", title: "Post a note", category: "Notes", keys: ["<leader> n p"],
        params: [CommandParameter("text", title: "Note")]
      ) { context in
        notes.posted.append(context.arguments.text("text") ?? "")
      },
      Command(
        id: "note.count", title: "Count notes", category: "Notes", keys: ["<leader> n c"],
        params: [CommandParameter("n", title: "How many", kind: .integer(1...5))]
      ) { context in
        notes.counted.append(context.arguments.integer("n") ?? 0)
      },
      Command(
        id: "note.listOnly", title: "Only on the list", category: "Notes",
        isAvailable: { $0.focus.focused == "items" }
      ) { _ in
        notes.posted.append("list only")
      },
    ])
    let keyboard = KeyboardController(host: host, dispatcher: dispatcher, quit: {})
    self.keyboard = keyboard
    let state = state
    host.setContent { Backdrop(state: state, notes: notes).commandOverlays(keyboard) }
    host.render()
  }

  // MARK: Which-key

  @Test func leaderShowsWhichKey() {
    host.type("\0")
    assertSnapshot(of: host, width: 80, height: 24)
    host.type("n")
    #expect(keyboard.pending.map(\.name) == ["Ctrl-Space", "n"])
    assertSnapshot(of: host, width: 80, height: 24, named: "notes-group")
    host.type("\u{1B}")
    #expect(keyboard.pending.isEmpty)
    #expect(!host.plain(width: 80, height: 24).contains("Esc cancel"))
  }

  @Test func leaderDigitsGoToTabs() {
    host.type("\0")
    host.type("3")
    #expect(state.selectedTabID == "c")
    host.type("\0")
    host.type("9")  // no ninth tab: nothing happens
    #expect(state.selectedTabID == "c")
    #expect(keyboard.lastFailure?.contains("tab") == true)
    host.type("\0")
    host.type("t")
    host.type("n")
    #expect(state.selectedTabID == "a")
  }

  // MARK: Palette

  @Test func paletteSnapshots() {
    host.type("\u{10}")  // Ctrl-P
    #expect(keyboard.palette.isOpen)
    #expect(host.focus.focused == PaletteModel.fieldID)
    assertSnapshot(of: host, width: 80, height: 24)
    host.type("tab")
    assertSnapshot(of: host, width: 80, height: 24, named: "query")
    host.type("\u{1B}[B")  // ArrowDown
    #expect(keyboard.palette.list.selection == 1)
  }

  @Test func paletteRunsTheSelectedCommandWhereFocusWas() {
    host.focus.focus("items")
    host.render()
    host.type("\u{10}")
    host.type("only list")
    #expect(keyboard.paletteItems.first?.value == "note.listOnly")
    host.type("\r")
    #expect(!keyboard.palette.isOpen)
    #expect(notes.posted == ["list only"])
    #expect(host.focus.focused == "items")
    // Elsewhere it isn't offered.
    host.focus.focus("other")
    host.type("\u{10}")
    #expect(!keyboard.paletteItems.contains { $0.value == "note.listOnly" })
  }

  @Test func paletteNavigationCommandsActOnTheUnderlyingList() {
    host.focus.focus("items")
    host.render()
    host.type("\u{10}")
    host.type("move down")
    #expect(keyboard.paletteItems.first?.value == "list.down")
    host.type("\r")
    #expect(notes.list.selection == 1)
  }

  @Test func palettePromptsForAChoice() {
    host.type("\u{10}")
    host.type("go to tab")
    host.type("\r")
    #expect(keyboard.palette.isOpen)
    #expect(keyboard.palette.title == "Go to tab › Tab")
    assertSnapshot(of: host, width: 80, height: 24)
    host.type("gam")
    #expect(keyboard.paletteItems.map(\.title) == ["3 gamma"])
    host.type("\r")
    #expect(!keyboard.palette.isOpen)
    #expect(state.selectedTabID == "c")
  }

  @Test func palettePromptsForTextAndValidatesNumbers() {
    host.type("\u{10}")
    host.type("post a note\r")
    #expect(keyboard.palette.title == "Post a note › Note")
    host.type("hello there\r")
    #expect(notes.posted == ["hello there"])

    host.type("\0")
    host.type("n")
    host.type("c")  // keys without the argument open the prompt too
    #expect(keyboard.palette.title == "Count notes › How many")
    host.type("lots\r")
    #expect(keyboard.palette.error == "Enter a number")
    host.renderIfNeeded()
    host.setText("", for: PaletteModel.fieldID)
    host.type("9\r")
    #expect(keyboard.palette.error == "Not a valid how many")
    host.setText("", for: PaletteModel.fieldID)
    host.type("4\r")
    #expect(notes.counted == [4])
    #expect(!keyboard.palette.isOpen)
  }

  @Test func escClosesThePaletteAndFocusReturns() {
    host.focus.focus("items")
    host.render()
    host.type("\u{10}")
    host.type("x")
    host.type("\u{1B}")
    #expect(!keyboard.palette.isOpen)
    #expect(host.focus.focused == "items")
    // Reopening starts empty.
    host.type("\u{10}")
    #expect(host.text(of: PaletteModel.fieldID) == "")
    #expect(keyboard.palette.query == "")
  }

  @Test func recentCommandsComeFirst() {
    host.type("\0")
    host.type("t")
    host.type("p")
    host.type("\u{10}")
    #expect(keyboard.paletteItems.first?.value == "tab.previous")
  }

  // MARK: Help

  @Test func helpListsAvailableCommandsWithKeys() {
    host.type("?")
    #expect(keyboard.isHelpVisible)
    assertSnapshot(of: host, width: 80, height: 24)
    #expect(keyboard.keyHint(for: TabCommands.goto, limit: 2) == "^Space 1…9, Alt-1…9")
    host.type("j")  // scrolls the help, not the list behind it
    #expect(notes.list.selection == 0)
    host.type("?")
    #expect(!keyboard.isHelpVisible)
  }
}
