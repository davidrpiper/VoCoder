import Testing
import VoCoderCore
import VoCoderFakes

@testable import VoCoderUI

@MainActor
final class GreetingTab: ViewTab {
  let id: TabID = "greeting"
  let title = "Greeting"
  var body: some View { Text("Hello from a tab") }
}

@MainActor
@Suite struct ViewTabTests {
  @Test func viewTabFactoriesRegisterAndDraw() throws {
    var registry = ModuleRegistry(module: "test")
    registry.add(tabs: TabFactory(id: "greeting", placement: .home) { _ in [GreetingTab()] })
    #expect(registry.tabFactories.map(\.id) == ["greeting"])
    #expect(registry.owner(of: "greeting", in: .tabs) == "test")
    let tab = try #require(try registry.tabFactories.first?.makeTabs(in: TabContext()).first)
    #expect(render(TabContent(tab), width: 20) == lines("Hello from a tab"))
  }

  @Test func tabsWithoutAViewShowANote() {
    #expect(
      render(TabContent(FakeTab(id: "x", title: "Plain")), width: 24)
        == lines("   Plain has no view"))
  }

  @Test func badgeLabels() {
    let badges: [TabBadge] = [
      .none, .count(0), .count(3), .working, .needsYou, .finished, .error, .text("10:30"),
    ]
    #expect(badges.map(\.label) == ["", "", "3", "◐", "●", "✓", "✗", "10:30"])
  }
}
