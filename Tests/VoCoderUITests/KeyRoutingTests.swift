import Observation
import Testing
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

@MainActor
@Suite struct KeyRoutingTests {
  let form = Form()
  let host: UIHost

  init() {
    let form = form
    host = UIHost(theme: .dark) { FormView(form: form) }
    host.onUnhandledKey = { key in
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

  @Test func unmappedAndUnhandledKeysReachTheFallback() {
    host.focus.focus("list")
    host.type("\u{1B}[C")  // ArrowRight: mapped, but nothing handles it
    host.type("q")
    #expect(form.unhandled == ["ArrowRight", "q"])
  }

  @Test func keyMapIsReplaceable() {
    host.focus.focus("list")
    host.keyMap = KeyMap(["n": .moveDown])
    host.type("n")
    host.type("j")
    #expect(form.list.selection == 1)
    #expect(form.unhandled == ["j"])
  }
}
