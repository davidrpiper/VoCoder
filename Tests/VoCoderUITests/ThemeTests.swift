import Foundation
import Testing
import VoCoderUI
import VoCoderUIBridge
import VoCoderUITestSupport

private struct Swatches: View {
  var body: some View {
    VStack {
      for role in ThemeRole.allCases {
        HStack {
          Text(role.rawValue).frame(width: .exactly(18))
          Text(" sample ").foreground(.role(role))
          Text("      ").background(.role(role))
        }
      }
    }
  }
}

@MainActor
@Suite struct ThemeTests {
  @Test func swatchSnapshots() {
    for theme in [Theme.dark, .light] {
      assertSnapshot(of: Swatches(), width: 34, theme: theme, format: .ansi(), named: theme.name)
      assertSnapshot(
        of: Swatches(), width: 34, theme: theme, format: .ansi(.palette256),
        named: theme.name)
    }
  }

  /// Every colour a theme sets stays distinct from the others after degrading to 256 colours,
  /// except roles that deliberately share a colour (focus is the accent).
  @Test(arguments: Appearance.allCases)
  func rolesStayDistinctIn256Colors(appearance: Appearance) {
    let theme = Theme.builtIn(appearance)
    var codes: [String: [ThemeRole]] = [:]
    for role in ThemeRole.allCases where theme[role] != nil {
      let host = UIHost(theme: theme) { Text("x").foreground(.role(role)) }
      host.render()
      let ansi = host.renderer.renderToString(width: 1, height: 1, colorDepth: .palette256)
      let code = ansi.firstMatch(of: /\[38;5;(\d+)m/).map { String($0.1) } ?? "none"
      codes[code, default: []].append(role)
    }
    let shared = codes.values.filter { $0.count > 1 }.map { Set($0) }
    #expect(shared == [] || shared == [[.accent, .focus]])
    #expect(codes["none"] == nil)
  }

  @Test func unsetRolesUseTheTerminalDefault() {
    let host = UIHost(theme: .dark) { Text("x").foreground(.text).background(.selectionText) }
    host.render()
    let ansi = host.renderer.renderToString(width: 1, height: 1, ansi: true)
    #expect(!ansi.contains("[38;") && !ansi.contains("[48;"))
  }

  @Test func automaticFollowsSystemAppearance() throws {
    let defaults = try #require(UserDefaults(suiteName: "vocoder.tests.theme"))
    defer { defaults.removePersistentDomain(forName: "vocoder.tests.theme") }
    defaults.set("Dark", forKey: "AppleInterfaceStyle")
    #expect(Theme.automatic(defaults: defaults) == .dark)
    defaults.removeObject(forKey: "AppleInterfaceStyle")
    // The global domain is in the search list; only check our override took effect above and
    // that "no value" maps to light when the global value is absent.
    if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == nil {
      #expect(Theme.automatic(defaults: defaults) == .light)
    }
  }

  @Test func themeChangeInvalidates() {
    let host = UIHost(theme: .dark) { Text("x") }
    host.render()
    #expect(!host.needsRender)
    host.theme = .light
    #expect(host.needsRender)
  }
}
