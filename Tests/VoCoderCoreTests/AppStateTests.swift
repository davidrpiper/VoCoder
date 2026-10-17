import Foundation
import Observation
import Synchronization
import Testing
import VoCoderFakes

@testable import VoCoderCore

@MainActor
@Suite struct AppStateTests {
  let state = AppState()
  let a = FakeTab(id: "a")
  let b = FakeTab(id: "b")
  let c = FakeTab(id: "c")

  func openAll() {
    for tab in [a, b, c] { state.open(tab) }
  }

  @Test func firstOpenedTabIsSelectedAndActivated() {
    openAll()
    #expect(state.tabs.map(\.id) == ["a", "b", "c"])
    #expect(state.selectedTabID == "a")
    #expect(a.lifecycle == ["activate"])
    #expect(b.lifecycle.isEmpty)
  }

  @Test func openAtIndexAndRejectDuplicates() {
    openAll()
    #expect(state.open(FakeTab(id: "x"), at: 1))
    #expect(!state.open(FakeTab(id: "b")))
    #expect(state.tabs.map(\.id) == ["a", "x", "b", "c"])
  }

  @Test func selectionDrivesLifecycle() {
    openAll()
    #expect(state.select("c"))
    #expect(state.select("c"), "reselecting is a no-op")
    #expect(!state.select("missing"))
    #expect(state.selectedTab === c)
    #expect(a.lifecycle == ["activate", "deactivate"])
    #expect(c.lifecycle == ["activate"])
  }

  @Test func closingTheSelectedTabSelectsTheNextOrPrevious() {
    openAll()
    state.select("b")
    state.close("b")
    #expect(state.selectedTabID == "c")
    #expect(b.lifecycle == ["activate", "deactivate", "close"])
    state.close("c")
    #expect(state.selectedTabID == "a")
    state.close("a")
    #expect(state.selectedTabID == nil)
    #expect(state.tabs.isEmpty)
    #expect(!state.close("a"))
  }

  @Test func closingAnotherTabKeepsTheSelection() {
    openAll()
    state.close("b")
    #expect(state.selectedTabID == "a")
    #expect(b.lifecycle == ["close"])
  }

  @Test func moveReordersAndClamps() {
    openAll()
    #expect(state.move("a", to: 2))
    #expect(state.tabs.map(\.id) == ["b", "c", "a"])
    #expect(state.move("c", to: -5))
    #expect(state.tabs.map(\.id) == ["c", "b", "a"])
    #expect(state.move("c", to: 99))
    #expect(state.tabs.map(\.id) == ["b", "a", "c"])
    #expect(!state.move("missing", to: 0))
    #expect(state.selectedTabID == "a", "moving keeps the selection")
  }

  @Test func tabsMatchByTitleOrAlias() {
    state.open(FakeTab(id: "api", title: "api-server", aliases: ["api", "the backend"]))
    state.open(FakeTab(id: "web", title: "Web", aliases: ["frontend"]))
    state.open(FakeTab(id: "web2", title: "web-old", aliases: ["frontend"]))
    #expect(state.tab(matching: "API-server")?.id == "api")
    #expect(state.tab(matching: " the api ")?.id == "api")
    #expect(state.tab(matching: "backend")?.id == "api", "a leading 'the' is dropped on both sides")
    #expect(state.tab(matching: "web")?.id == "web")
    #expect(state.tab(matching: "frontend") == nil, "ambiguous")
    #expect(state.tab(matching: "") == nil)
    #expect(state.tab(matching: "nothing") == nil)
  }

  @Test func closeAllClosesEveryTab() {
    openAll()
    state.closeAll()
    #expect(state.tabs.isEmpty)
    #expect([a, b, c].allSatisfy { $0.lifecycle.last == "close" })
  }

  // MARK: Attention

  func item(_ id: AttentionItemID, _ title: String = "t", expiry: Date? = nil) -> AttentionItem {
    AttentionItem(id: id, source: "test", priority: .soon, title: title, expiry: expiry)
  }

  @Test func postingReplacesItemsWithTheSameID() {
    state.post(item("one", "first"))
    state.post(item("two"))
    state.post(item("one", "updated"))
    #expect(state.attention.map(\.id) == ["one", "two"])
    #expect(state.attention.first?.title == "updated")
    #expect(state.attention.first?.spoken == "updated", "spoken defaults to the title")
  }

  @Test func expiredItemsAreDroppedOrRemoved() {
    let now = Date(timeIntervalSince1970: 100)
    state.post(item("stale", expiry: now), now: now)
    #expect(state.attention.isEmpty)
    state.post(item("soon", expiry: now + 10), now: now)
    state.post(item("later", expiry: now + 60), now: now)
    state.post(item("soon", expiry: now - 1), now: now)
    #expect(state.attention.map(\.id) == ["later"], "posting an expired update removes it")
    state.removeExpiredAttention(now: now + 60)
    #expect(state.attention.isEmpty)
  }

  @Test func dismissRemovesAnItem() {
    state.post(item("one"))
    state.post(item("two"))
    state.dismissAttention("one")
    #expect(state.attention.map(\.id) == ["two"])
  }

  @Test func observationSeesTabAndAttentionChanges() {
    let changes = Mutex(0)
    withObservationTracking {
      _ = state.tabs
      _ = state.attention
    } onChange: {
      changes.withLock { $0 += 1 }
    }
    state.open(a)
    #expect(changes.withLock { $0 } == 1)
  }
}
