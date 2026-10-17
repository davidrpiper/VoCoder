import Observation
import Testing
import VoCoderCore
import VoCoderUI

@MainActor
@Observable
final class Form {
  let list = ListState()
  var activated: [Int] = []
  var submitted: [String] = []
  var changes: [String] = []
  var unhandled: [String] = []
  var cancelled = 0
}

struct FormView: View {
  let form: Form

  var body: some View {
    VStack {
      TextField(
        "name", placeholder: "name",
        onChange: { form.changes.append($0) }, onSubmit: { form.submitted.append($0) })
      ListView(
        "list", state: form.list, items: ["one", "two", "three"],
        onActivate: { form.activated.append($0) }
      ) { item, _ in Text(item) }
    }
    .focusScope("form") { action in
      guard action == .cancel else { return false }
      form.cancelled += 1
      return true
    }
  }
}

/// Keys → keymap → navigation commands → `UIAction`s along the focus path.
@MainActor
@Suite struct KeyRoutingTests {
  let form = Form()
  let host = UIHost(theme: .dark)
  let keyboard: KeyboardController

  init() {
    let form = form
    let keyboard = KeyboardController(
      host: host, dispatcher: CommandDispatcher(state: AppState()), quit: {})
    self.keyboard = keyboard
    host.setContent { FormView(form: form).commandOverlays(keyboard) }
    let handle = host.onKey
    host.onKey = { key in
      if handle?(key) == true { return true }
      form.unhandled.append(key)
      return true
    }
    host.render()
  }

  @Test func typingGoesToTheFocusedField() {
    #expect(host.focus.focused == "name")
    #expect(host.renderer.focusedWidget == "name")
    host.type("hi")
    #expect(host.text(of: "name") == "hi")
    #expect(form.changes == ["h", "hi"])
    host.type("\r")
    #expect(form.submitted == ["hi"])
    #expect(form.unhandled.isEmpty)
  }

  @Test func tabMovesFocusAndTheWidgetFollows() {
    host.type("\t")
    #expect(host.focus.focused == "list")
    #expect(host.renderer.focusedWidget == nil)
    host.type("x")  // no longer typed into the field
    #expect(host.text(of: "name") == "")
    #expect(form.unhandled == ["x"])
    host.type("\u{1B}[Z")  // Shift-Tab
    #expect(host.renderer.focusedWidget == "name")
  }

  @Test func listKeysMoveTheSelectionAndActivate() {
    host.focus.focus("list")
    host.type("j")
    host.type("\u{1B}[B")  // ArrowDown
    host.type("j")  // already at the end: handled, doesn't bubble
    #expect(form.list.selection == 2)
    host.type("k")
    host.type("\r")
    #expect(form.activated == [1])
    host.type("g")
    #expect(form.list.selection == 0)
    host.type("G")
    #expect(form.list.selection == 2)
    #expect(form.unhandled.isEmpty)
  }

  @Test func escBubblesFromTheFieldToTheScope() {
    host.type("\u{1B}")
    #expect(form.cancelled == 1)
    #expect(form.unhandled.isEmpty)
  }

  @Test func unboundKeysFallThrough() {
    host.focus.focus("list")
    host.type("\u{1B}[C")  // ArrowRight: bound to ui.right, which nothing here acts on
    host.type("q")
    #expect(form.unhandled == ["q"])
  }

  @Test func overridesReplaceDefaultBindings() {
    host.focus.focus("list")
    keyboard.rebuildKeymap(overrides: KeyBindingOverrides(bindings: ["list.down": ["n"]]))
    host.type("n")
    host.type("j")
    #expect(form.list.selection == 1)
    #expect(form.unhandled == ["j"])
  }

  @Test func leaderSequencesRunCommands() {
    host.type("\0")  // Ctrl-Space
    #expect(keyboard.pending.map(\.name) == ["Ctrl-Space"])
    host.type("?")  // reaches the keymap, not the focused field
    #expect(keyboard.pending.isEmpty)
    #expect(keyboard.isHelpVisible)
    #expect(host.text(of: "name") == "")
    #expect(host.focus.focused == CommandOverlays.helpScrollID)
    host.type("\u{1B}")  // Esc closes help
    #expect(!keyboard.isHelpVisible)
    #expect(host.focus.focused == "name")
  }

  @Test func escCancelsAPendingSequenceWithoutRunningCancel() {
    host.type("\0")
    host.type("\u{1B}")
    #expect(keyboard.pending.isEmpty)
    #expect(form.cancelled == 0)
    host.type("\0")
    host.type("z")  // continues nothing: swallowed
    #expect(keyboard.pending.isEmpty)
    #expect(form.unhandled.isEmpty)
  }
}
