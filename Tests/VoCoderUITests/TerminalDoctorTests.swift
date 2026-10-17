import Testing
import VoCoderCore
import VoCoderTestSupport

@testable import VoCoderUI

@Suite struct TerminalDoctorTests {
  let inputSourcePrevious = SymbolicHotKey(id: 60, enabled: true, keyCode: 49, modifiers: 0x40000)

  @Test func terminalKind() async {
    #expect(TerminalKind(termProgram: "Apple_Terminal") == .terminalApp)
    #expect(TerminalKind(termProgram: "ghostty") == .ghostty)
    #expect(TerminalKind(termProgram: nil) == .unknown)
    #expect(await TerminalDoctorChecks.terminal(.init(terminal: .ghostty)).run() == .ok("Ghostty"))
    let tmux = await TerminalDoctorChecks.terminal(.init(terminal: .other("tmux"))).run()
    #expect(tmux.status == .warning)
    let iterm = await TerminalDoctorChecks.terminal(.init(terminal: .other("iTerm.app"))).run()
    #expect(iterm.message == "iTerm.app isn't tested")
  }

  @Test func optionAsMetaInTerminalApp() async {
    let on = TerminalEnvironment(terminal: .terminalApp, terminalAppProfile: ("Basic", true))
    #expect(await TerminalDoctorChecks.optionAsMeta(on).run() == .ok("on in profile 'Basic'"))
    let off = TerminalEnvironment(terminal: .terminalApp, terminalAppProfile: ("Basic", false))
    let result = await TerminalDoctorChecks.optionAsMeta(off).run()
    #expect(result.status == .warning)
    #expect(result.hint?.contains("Profiles → Basic → Keyboard → Use Option as Meta key") == true)
    let unreadable = TerminalEnvironment(terminal: .terminalApp)
    #expect(await TerminalDoctorChecks.optionAsMeta(unreadable).run().status == .skipped)
  }

  @Test func optionAsAltInGhostty() async {
    func check(_ config: String?) async -> DoctorResult {
      await TerminalDoctorChecks.optionAsMeta(.init(terminal: .ghostty, ghosttyConfig: config))
        .run()
    }
    #expect(await check(nil).status == .warning)
    #expect(await check("font-size = 14\n").status == .warning)
    #expect(await check("macos-option-as-alt = left\n") == .ok("macos-option-as-alt = left"))
    // The last assignment wins.
    #expect(
      await check("macos-option-as-alt = true\nmacos-option-as-alt = false\n").status == .warning)
    #expect(TerminalDoctorChecks.ghosttyOptionAsAlt("macos-option-as-alt=\"true\"") == "true")
    let other = TerminalEnvironment(terminal: .other("WezTerm"))
    #expect(await TerminalDoctorChecks.optionAsMeta(other).run().status == .skipped)
  }

  @Test func inputSourceShortcutTakesTheLeaderOnlyWithSeveralSources() async {
    func check(_ keys: [SymbolicHotKey], sources: Int, leader: KeyChord = .leaderDefault) async
      -> DoctorResult
    {
      await TerminalDoctorChecks.leaderShortcut(
        .init(terminal: .terminalApp, hotKeys: keys, keyboardInputSources: sources), leader: leader
      ).run()
    }
    #expect(await check([inputSourcePrevious], sources: 1).status == .ok)
    let taken = await check([inputSourcePrevious], sources: 2)
    #expect(taken.status == .warning)
    #expect(taken.message.hasPrefix("macOS uses Ctrl-Space to switch input sources (2 enabled)"))
    #expect(taken.hint?.contains("Keyboard Shortcuts → Input Sources") == true)
    let disabled = SymbolicHotKey(id: 60, enabled: false, keyCode: 49, modifiers: 0x40000)
    #expect(await check([disabled], sources: 3).status == .ok)
    // Another shortcut on Ctrl-Space takes it regardless of input sources.
    let custom = SymbolicHotKey(id: 200, enabled: true, keyCode: 49, modifiers: 0x40000)
    #expect(await check([custom], sources: 1).status == .warning)
    // A different leader isn't affected.
    let other = await check([inputSourcePrevious], sources: 2, leader: KeyChord("ctrl+b")!)
    #expect(other.status == .ok)
  }

  @Test func checksPassTheContract() async {
    let environments = [
      TerminalEnvironment(terminal: .unknown),
      TerminalEnvironment(
        terminal: .terminalApp, terminalAppProfile: ("Basic", false),
        hotKeys: [inputSourcePrevious],
        keyboardInputSources: 2),
      TerminalEnvironment(terminal: .ghostty, ghosttyConfig: "macos-option-as-alt = true"),
    ]
    for environment in environments {
      for check in TerminalDoctorChecks.all(environment, leader: .leaderDefault) {
        await DoctorCheckContract.verify(check)
      }
    }
  }

  @Test func themePreference() {
    #expect(Theme.preferred(.dark) == .dark)
    #expect(Theme.preferred(.light) == .light)
  }
}
