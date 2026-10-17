// The keyboard overlays drawn over the app: the which-key popup for a pending key sequence, the
// command palette and the help overlay. Compose with `.commandOverlays(keyboard)`.
import VoCoderCore

extension View {
  /// Draws `keyboard`'s overlays (which-key, palette, help) on top of this view.
  public func commandOverlays(_ keyboard: KeyboardController) -> some View {
    ZStack {
      self
      CommandOverlays(keyboard: keyboard)
    }
  }
}

public struct CommandOverlays: View {
  public static let helpScopeID: FocusID = "help"
  public static let helpScrollID: FocusID = "help.scroll"

  let keyboard: KeyboardController

  public init(keyboard: KeyboardController) { self.keyboard = keyboard }

  public var body: some View {
    if keyboard.palette.isOpen {
      PaletteView(keyboard: keyboard)
    } else if keyboard.isHelpVisible {
      HelpView(keyboard: keyboard)
    }
    if !keyboard.pending.isEmpty {
      WhichKeyView(keyboard: keyboard)
    }
  }
}

// MARK: Which-key

/// The keys that can follow the pending prefix, at the bottom of the screen.
struct WhichKeyView: View {
  let keyboard: KeyboardController

  struct Entry {
    let keys: String
    let title: String
    let isGroup: Bool
  }

  var body: some View {
    let entries = Self.entries(keyboard.keymap, keyboard.pending, keyboard.dispatcher)
    let columns = 3
    let rows = stride(from: 0, to: entries.count, by: columns).map {
      Array(entries[$0..<min($0 + columns, entries.count)])
    }
    VStack {
      Spacer()
      VStack {
        Grid(
          rows.map { row in
            row.map { entry -> any View in
              HStack {
                Text(entry.keys).foreground(.accent).bold()
                Text(" " + entry.title + "   ").foreground(entry.isGroup ? .info : nil)
              }
            }
          })
        Text("Esc cancel").foreground(.muted)
      }
      .border(.rounded, title: keyboard.keymap.display(keyboard.pending) + " …", color: .focus)
      .clearUnder()
    }
  }

  /// One row per next key; digits bound to the same command collapse into "1…9".
  static func entries(_ keymap: Keymap, _ prefix: [KeyChord], _ dispatcher: CommandDispatcher)
    -> [Entry]
  {
    var entries: [Entry] = []
    var digitRun: (first: String, last: String, command: CommandID)?
    func flushDigits() {
      guard let run = digitRun else { return }
      let title = dispatcher[run.command]?.title ?? run.command.rawValue
      let keys = run.first == run.last ? run.first : "\(run.first)…\(run.last)"
      entries.append(Entry(keys: keys, title: title, isGroup: false))
      digitRun = nil
    }
    for continuation in keymap.continuations(after: prefix) {
      let key = continuation.chord.displayName
      if continuation.isGroup {
        flushDigits()
        let categories = Set(continuation.group.compactMap { dispatcher[$0]?.category })
        let title =
          categories.count == 1 ? "+" + categories.first! : "+\(continuation.group.count) commands"
        entries.append(Entry(keys: key, title: title, isGroup: true))
        continue
      }
      let command = continuation.targets[0].command
      if key.count == 1, key.first!.isNumber {
        if let run = digitRun, run.command == command {
          digitRun = (run.first, key, command)
          continue
        }
        flushDigits()
        digitRun = (key, key, command)
        continue
      }
      flushDigits()
      let titles = continuation.targets.compactMap { dispatcher[$0.command]?.title }
      entries.append(Entry(keys: key, title: titles.first ?? command.rawValue, isGroup: false))
    }
    flushDigits()
    return entries
  }
}

// MARK: Palette

struct PaletteView: View {
  let keyboard: KeyboardController

  var body: some View {
    let palette = keyboard.palette
    let items = keyboard.paletteItems
    let selected = palette.list.selectedIndex(count: items.count)
    let window = Self.window(count: items.count, selected: selected, rows: palette.visibleRows)
    VStack {
      Spacer().frame(height: .exactly(1))
      HStack {
        Spacer()
        VStack {
          HStack {
            Text("› ").foreground(.accent)
            TextField(
              PaletteModel.fieldID, placeholder: placeholder,
              onAction: { keyboard.paletteAction($0) },
              onChange: { keyboard.paletteQueryChanged($0) },
              onSubmit: { keyboard.paletteSubmitted($0) })
          }
          Divider()
          if let error = palette.error {
            Text(error).foreground(.danger)
          }
          if items.isEmpty {
            Text(emptyText).foreground(.muted)
          }
          for index in window {
            row(items[index], selected: index == selected)
          }
          if items.count > window.count {
            Text("\(items.count) results · ↑↓ select · Enter run · Esc close").foreground(.muted)
          } else {
            Text("↑↓ select · Enter run · Esc close").foreground(.muted)
          }
        }
        .border(.rounded, title: palette.title, color: .focus)
        .frame(width: .exactly(64))
        .clearUnder()
        Spacer()
      }
      Spacer()
    }
    .focusScope(PaletteModel.scopeID, trap: true)
  }

  private var placeholder: String {
    switch keyboard.palette.stage {
    case .commands: return "Type a command"
    case .parameter(let command, let index, _):
      switch command.params[index].kind {
      case .choice: return "Filter"
      case .integer(let range?): return "A number from \(range.lowerBound) to \(range.upperBound)"
      case .integer(nil): return "A number"
      case .text: return command.params[index].title
      }
    }
  }

  private var emptyText: String {
    switch keyboard.palette.stage {
    case .commands: return "No matching commands"
    case .parameter(let command, let index, _):
      if case .choice = command.params[index].kind { return "No matches" }
      return "Enter to continue"
    }
  }

  private func row(_ item: PaletteItem, selected: Bool) -> some View {
    HStack {
      Text(selected ? "› " : "  ")
      Text(item.title)
      Spacer()
      Text(item.detail).foreground(.muted)
      Text(item.keys.isEmpty ? "" : "  " + item.keys).foreground(.accent)
    }
    .foreground(selected ? .selectionText : nil)
    .background(selected ? .selection : nil)
  }

  /// The rows to show so `selected` is visible.
  static func window(count: Int, selected: Int?, rows: Int) -> Range<Int> {
    guard count > rows else { return 0..<count }
    let start = min(max((selected ?? 0) - rows + 1, 0), count - rows)
    return start..<(start + rows)
  }
}

// MARK: Help

struct HelpView: View {
  let keyboard: KeyboardController

  var body: some View {
    VStack {
      Spacer().frame(height: .exactly(1))
      HStack {
        Spacer()
        VStack {
          ScrollView(CommandOverlays.helpScrollID, state: keyboard.helpScroll) {
            for section in keyboard.helpSections {
              Text(section.category).bold().foreground(.accent)
              for entry in section.entries {
                HStack {
                  Text("  " + entry.title)
                  Spacer()
                  Text(entry.keys + " ").foreground(.muted)
                }
              }
            }
          }
          .flex()
          Divider()
          Text("^P palette · ^Space leader · j/k scroll · Esc close").foreground(.muted)
        }
        .border(.rounded, title: "Help", color: .focus)
        .frame(width: .exactly(64))
        .clearUnder()
        Spacer()
      }
      .flex()
      Spacer().frame(height: .exactly(1))
    }
    .focusScope(CommandOverlays.helpScopeID, trap: true, onAction: { keyboard.helpAction($0) })
  }
}
