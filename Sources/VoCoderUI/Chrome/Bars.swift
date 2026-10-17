// The chrome's bars (DESIGN §3.1): the tab bar at the top, the voice and hint bars at the bottom.
import VoCoderCore

/// "1 Home 2  2 vocoder ◐  3 api-server ●": numbered tabs with coloured badges, the selected one
/// highlighted. When the tabs don't fit, the selected one stays visible and "‹n" / "n›" count
/// the hidden ones.
struct TabBarView: View {
  let state: AppState

  var body: some View {
    let tabs = state.tabs
    let selected = tabs.firstIndex { $0.id == state.selectedTabID } ?? 0
    if tabs.isEmpty {
      Text(" no tabs").foreground(.muted)
    } else {
      Strip(keepingVisible: selected) {
        for (index, tab) in tabs.enumerated() {
          Self.label(tab, number: index + 1, selected: index == selected)
        }
      }
    }
  }

  static func label(_ tab: any Tab, number: Int, selected: Bool) -> some View {
    let badge = tab.badge.label
    return HStack {
      Text(" " + (number <= 9 ? "\(number) " : "")).foreground(selected ? nil : .muted)
      Text(tab.title).style(selected ? .bold : [])
      if !badge.isEmpty {
        Text(" " + badge).foreground(badgeColor(tab.badge)).bold()
      }
      Text(" ")
    }
    .foreground(selected ? .selectionText : nil)
    .background(selected ? .selection : nil)
  }

  static func badgeColor(_ badge: TabBadge) -> Color? {
    switch badge {
    case .none: nil
    case .count: .accent
    case .working: .info
    case .needsYou: .warning
    case .finished: .success
    case .error: .danger
    case .text: .muted
    }
  }
}

/// Mic state, the live transcript or what is being said, and the attention queue length.
/// Static (voice off) until Phase 2 drives `AppState.voice`.
struct VoiceBarView: View {
  let state: AppState

  var body: some View {
    let voice = state.voice
    let queue = state.attention.count
    HStack {
      Text(" " + Self.mic(voice.mic) + " ").foreground(Self.color(voice.mic)).bold()
      Text(Self.label(voice.mic)).foreground(Self.color(voice.mic))
      if !voice.transcript.isEmpty, voice.mic == .listening || voice.mic == .thinking {
        Text("  “" + voice.transcript + "”")
      }
      Spacer()
      if !voice.speaking.isEmpty, voice.mic == .speaking {
        Text("⏵ " + voice.speaking + "  ").foreground(.accent)
      }
      Text("queue: \(queue) ").foreground(queue > 0 ? .warning : .muted)
    }
  }

  static func mic(_ mic: VoiceStatus.Mic) -> String {
    switch mic {
    case .off, .idle: "○"
    case .listening: "●"
    case .thinking: "◌"
    case .speaking: "▶"
    }
  }

  static func label(_ mic: VoiceStatus.Mic) -> String {
    switch mic {
    case .off: "voice off"
    case .idle: "idle"
    case .listening: "LISTENING"
    case .thinking: "thinking…"
    case .speaking: "speaking"
    }
  }

  static func color(_ mic: VoiceStatus.Mic) -> Color {
    switch mic {
    case .off, .idle: .muted
    case .listening: .danger
    case .thinking: .info
    case .speaking: .accent
    }
  }
}

/// Key hints: the leader, the selected tab's hint commands that are available now, then the
/// palette and help. Hints that don't fit are left out whole ("n›" counts them).
struct HintBarView: View {
  let keyboard: KeyboardController

  var body: some View {
    Strip(keepingVisible: 0) {
      for hint in hints {
        HStack {
          Text(" " + hint.keys).foreground(.accent)
          Text(" " + hint.title + "  ").foreground(.muted)
        }
      }
    }
  }

  var hints: [(keys: String, title: String)] {
    let keymap = keyboard.keymap
    var hints = [(keys: keymap.display([keymap.leader]), title: "leader")]
    let dispatcher = keyboard.dispatcher
    let tabHints = dispatcher.state.selectedTab?.hintCommands ?? []
    for id in tabHints + [NavigationCommands.palette, NavigationCommands.help]
    where dispatcher.isAvailable(id, source: .key) {
      let keys = keyboard.keyHint(for: id)
      guard !keys.isEmpty, let command = dispatcher[id] else { continue }
      hints.append(
        (keys, id == NavigationCommands.palette ? "palette" : command.title.lowercased()))
    }
    return hints
  }
}
