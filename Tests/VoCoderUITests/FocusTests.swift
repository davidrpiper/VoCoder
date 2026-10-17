import Observation
import Testing
import VoCoderUI

@MainActor
@Observable
final class Screen {
  var panes: [String: [String]] = ["left": ["a", "b", "c"], "right": ["d", "e"]]
  var modal = false
  var log: [String] = []
}

/// Two panes of focusable buttons and an optional modal with a trap scope.
struct ScreenView: View {
  let screen: Screen

  var body: some View {
    ZStack {
      HStack {
        pane("left")
        pane("right")
      }
      if screen.modal {
        VStack {
          button("ok")
          button("cancel")
        }
        .focusScope("modal", trap: true)
      }
    }
    .focusScope("root") { action in
      screen.log.append("root \(action.rawValue)")
      return action == .cancel
    }
  }

  private func pane(_ name: String) -> some View {
    VStack {
      for item in screen.panes[name] ?? [] { button(item) }
    }
    .focusScope(FocusID(name))
  }

  private func button(_ name: String) -> some View {
    Focusable(FocusID(name)) { focused in
      Text(focused ? "[\(name)]" : " \(name) ")
    }
  }
}

@MainActor
@Suite struct FocusTests {
  let screen = Screen()
  let host: UIHost

  init() {
    let screen = screen
    host = UIHost(theme: .dark) { ScreenView(screen: screen) }
    host.render()
  }

  var focused: String? { host.focus.focused?.rawValue }

  @Test func firstLeafIsFocusedInitially() {
    #expect(focused == "a")
    #expect(host.focus.path == ["root", "left", "a"])
    #expect(host.plain(width: 10).hasPrefix("[a]"))
  }

  @Test func traversalFollowsRenderOrderAndWraps() {
    var order: [String] = []
    for _ in 0..<6 {
      host.focus.focusNext()
      order.append(focused ?? "-")
    }
    #expect(order == ["b", "c", "d", "e", "a", "b"])
    host.focus.focusPrevious()
    host.focus.focusPrevious()
    #expect(focused == "e")
  }

  @Test func focusingAScopeReturnsToItsLastLeaf() {
    host.focus.focus("e")
    host.focus.focus("b")
    #expect(host.focus.focus("right"))
    #expect(focused == "e")
    #expect(host.focus.focus("left"))
    #expect(focused == "b")
  }

  @Test func removedLeafHandsFocusToItsNeighbour() {
    host.focus.focus("c")
    screen.panes["left"] = ["a", "b"]
    host.render()
    #expect(focused == "b")
    // Emptying the pane moves on to the next survivor in render order.
    screen.panes["left"] = []
    host.render()
    #expect(focused == "d")
  }

  @Test func trapScopeConfinesFocus() {
    host.focus.focus("d")
    screen.modal = true
    host.render()
    #expect(focused == "ok")
    host.focus.focusNext()
    host.focus.focusNext()
    #expect(focused == "ok")
    #expect(!host.focus.focus("a"))  // outside the trap: deferred
    #expect(focused == "ok")
    screen.modal = false
    host.render()
    #expect(focused == "a")  // the deferred request applies once the trap is gone
  }

  @Test func closingAModalRestoresThePreviousFocus() {
    host.focus.focus("d")
    screen.modal = true
    host.render()
    screen.modal = false
    host.render()
    #expect(focused == "d")  // back to where it was before the modal
  }

  @Test func pendingFocusAppliesWhenRendered() {
    #expect(!host.focus.focus("f"))
    screen.panes["right"]?.append("f")
    host.render()
    #expect(focused == "f")
  }

  @Test func focusChangesInvalidateTheHost() {
    host.renderIfNeeded()
    #expect(!host.needsRender)
    host.focus.focusNext()
    #expect(host.needsRender)
    #expect(host.plain(width: 10).contains("[b]"))
  }

  @Test func actionsBubbleToScopes() {
    #expect(host.perform(.cancel))
    #expect(!host.perform(.activate))
    #expect(screen.log == ["root cancel", "root activate"])
  }

  @Test func noFocusablesMeansNoFocus() {
    let empty = UIHost(theme: .dark) { Text("nothing") }
    empty.render()
    #expect(empty.focus.focused == nil)
    #expect(!empty.focus.focusNext())
    #expect(!empty.perform(.moveDown))
  }

  @Test func duplicateIDsKeepTheFirst() {
    let dup = UIHost(theme: .dark) {
      VStack {
        Focusable("x") { Text($0 ? "first*" : "first") }
        Focusable("x") { Text($0 ? "second*" : "second") }
      }
    }
    dup.render()
    #expect(dup.plain(width: 10) == lines("first*", "second*"))
    #expect(!dup.focus.focusNext())
  }
}
