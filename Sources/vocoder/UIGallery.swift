// `vocoder ui-gallery` (hidden): the VoCoderUI views live in a real terminal, to check themes,
// colour degradation and focus by eye. Development only; its keys aren't commands.
import ArgumentParser
import Foundation
import Observation
import VoCoderCore
import VoCoderUI
import VoCoderUIBridge

struct UIGalleryCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ui-gallery",
    abstract: "Interactive gallery of the UI views (development).",
    shouldDisplay: false
  )

  enum ThemeChoice: String, ExpressibleByArgument, CaseIterable { case auto, dark, light }
  enum ColorChoice: String, ExpressibleByArgument, CaseIterable {
    case auto, mono
    case ansi16 = "16"
    case palette256 = "256"
    case truecolor
  }

  @Option(help: "Theme: auto (macOS appearance), dark or light.") var theme = ThemeChoice.auto
  @Option(help: "Colour depth: auto (detected), mono, 16, 256 or truecolor.")
  var colors = ColorChoice.auto

  func run() throws {
    Log.bootstrap(sink: FileLogSink(directory: Log.defaultDirectory))
    let theme = theme
    let colors = colors
    MainActor.assumeIsolated {
      let initialTheme: Theme =
        switch theme {
        case .auto: .automatic()
        case .dark: .dark
        case .light: .light
        }
      switch colors {
      case .auto: break
      case .mono: VCRenderer.colorDepth = .monochrome
      case .ansi16: VCRenderer.colorDepth = .palette16
      case .palette256: VCRenderer.colorDepth = .palette256
      case .truecolor: VCRenderer.colorDepth = .trueColor
      }
      UIGallery(theme: initialTheme).run()
    }
  }
}

@MainActor
@Observable
final class GalleryModel {
  var page = 0
  var colorDepth = VCRenderer.colorDepth
  var themeName = ""
  var lastAction = "–"
  var submitted: [String] = []
  var spinnerFrame = 0
  let issues = ListState()
  let table = ListState()
  let log = ScrollState(followsEnd: true)
  var logLines: [String] = (1...40).map { "log line \($0)" }

  static let pages = ["Theme", "List", "Table", "Form", "Layout"]

  let rows: [(key: String, title: String, status: String)] = (1...60).map {
    (
      "ENG-\(100 + $0)", "Sample issue number \($0) with a longer title",
      ["Todo", "In Progress", "Done"][$0 % 3]
    )
  }
}

@MainActor
final class UIGallery {
  private let model = GalleryModel()
  private let host: UIHost
  private let log = Log(category: "ui-gallery")
  private lazy var runLoop = TerminalRunLoop(renderer: host.renderer, log: log)
  private var timer: Timer?

  init(theme: Theme) {
    let model = model
    host = UIHost(theme: theme) { GalleryView(model: model) }
    model.themeName = theme.name
    host.onUnhandledKey = { [unowned self] key in self.handleKey(key) }
  }

  func run() {
    host.connect()
    host.render()
    timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [model] _ in
      MainActor.assumeIsolated { model.spinnerFrame += 1 }
    }
    log.info("ui gallery started")
    runLoop.run()
    timer?.invalidate()
    log.info("ui gallery exited")
  }

  /// "1"…"5", or F1…F5 (which also work while a text field has focus).
  private func pageNumber(_ key: String) -> Int? {
    let digits = key.hasPrefix("F") ? key.dropFirst() : Substring(key)
    return Int(digits).flatMap { (1...GalleryModel.pages.count).contains($0) ? $0 : nil }
  }

  private func handleKey(_ key: String) -> Bool {
    switch key {
    case "q", "Ctrl-c":
      host.renderer.stop()
    case "t":
      host.theme = host.theme == .dark ? .light : .dark
      model.themeName = host.theme.name
    case "c":
      let order: [VCColorDepth] = [.trueColor, .palette256, .palette16, .monochrome]
      let next = order[((order.firstIndex(of: model.colorDepth) ?? 0) + 1) % order.count]
      VCRenderer.colorDepth = next
      model.colorDepth = next
    case "a" where model.page == 4:
      model.logLines.append("log line \(model.logLines.count + 1)")
    case let key where pageNumber(key) != nil:
      model.page = pageNumber(key)! - 1
    default:
      model.lastAction = "unhandled \(key)"
      return false
    }
    return true
  }
}

private struct GalleryView: View {
  let model: GalleryModel

  var body: some View {
    VStack {
      HStack {
        TabBar(
          GalleryModel.pages.enumerated().map { "\($0.offset + 1) \($0.element)" },
          selected: model.page)
        Spacer()
        Text("theme \(model.themeName) · colours \(depthName) ").foreground(.muted)
      }
      Divider()
      page.flex()
      Divider()
      ContextReader { context in
        Text("focus: \(context.focused?.rawValue ?? "none") · last: \(model.lastAction)")
          .foreground(.muted)
      }
      Text(
        "1-5/F1-F5 page · Tab/Shift-Tab focus · j/k/PgUp/PgDn/g/G move · Enter · t theme · "
          + "c colours · q/Ctrl-C quit"
      ).dim()
    }
  }

  private var depthName: String {
    switch model.colorDepth {
    case .monochrome: "mono"
    case .palette16: "16"
    case .palette256: "256"
    default: "truecolor"
    }
  }

  @ViewBuilder private var page: some View {
    switch model.page {
    case 0: ThemePage()
    case 1: ListPage(model: model)
    case 2: TablePage(model: model)
    case 3: FormPage(model: model)
    default: LayoutPage(model: model)
    }
  }
}

private struct ThemePage: View {
  var body: some View {
    HStack {
      VStack {
        Text("Roles").bold()
        for role in ThemeRole.allCases {
          HStack {
            Text(role.rawValue).frame(width: .exactly(18))
            Text(" sample ").foreground(.role(role))
            Text("        ").background(.role(role))
          }
        }
      }
      .border(.rounded, title: "theme")
      VStack {
        Text("Styles").bold()
        Text("bold").bold()
        Text("dim").dim()
        Text("italic").italic()
        Text("underlined").underlined()
        Text("inverted").inverted()
        Text("strikethrough").strikethrough()
        Text("")
        Text("ANSI 16").bold()
        HStack {
          for color in ANSIColor.allCases { Text("  ").background(.ansi(color)) }
        }
        Text("RGB ramp").bold()
        HStack {
          for step in 0..<32 {
            Text(" ").background(.rgb(UInt8(step * 8), UInt8(255 - step * 8), 128))
          }
        }
      }
      .border(.rounded, title: "styles")
    }
  }
}

private struct ListPage: View {
  let model: GalleryModel

  var body: some View {
    HStack {
      ListView(
        "gallery.issues", state: model.issues, items: model.rows,
        onActivate: { model.lastAction = "activated \(model.rows[$0].key)" }
      ) { row, state in
        HStack {
          Text(state.isSelected ? "› " : "  ")
          Text(row.key).foreground(.accent)
          Text(" " + row.title)
        }
      }
      .focusPanel("gallery.issues", title: "Issues")
      .frame(width: .exactly(44))
      let selected = model.issues.selectedIndex(count: model.rows.count) ?? 0
      VStack {
        Text(model.rows[selected].key).bold().foreground(.accent)
        Paragraph(model.rows[selected].title)
        Text("Status: \(model.rows[selected].status)").foreground(statusColor(selected))
      }
      .border(.rounded, title: "Detail", color: .border)
      .flex()
    }
  }

  private func statusColor(_ index: Int) -> Color {
    switch model.rows[index].status {
    case "Done": .success
    case "In Progress": .warning
    default: .muted
    }
  }
}

private struct TablePage: View {
  let model: GalleryModel

  var body: some View {
    TableView(
      "gallery.table", state: model.table, items: model.rows,
      columns: [
        TableColumn("Key", width: .fixed(8)) { $0.key },
        TableColumn("Title", width: .flexible) { $0.title },
        TableColumn("Status", width: .fixed(12)) { $0.status },
      ],
      onActivate: { model.lastAction = "activated row \($0)" }
    )
    .focusPanel("gallery.table", title: "Table")
  }
}

private struct FormPage: View {
  let model: GalleryModel

  var body: some View {
    VStack {
      TextField(
        "gallery.name", placeholder: "your name",
        onSubmit: { model.submitted.append($0) }
      )
      .focusPanel("gallery.name", title: "Name (Enter submits)")
      TextField("gallery.notes", placeholder: "multi-line notes", multiline: true)
        .frame(height: .exactly(4))
        .focusPanel("gallery.notes", title: "Notes")
      Text("Submitted: \(model.submitted.joined(separator: ", "))")
      Text("Typed keys go to the focused field; Tab/Shift-Tab/Esc still reach the app.")
        .foreground(.muted)
    }
  }
}

private struct LayoutPage: View {
  let model: GalleryModel

  var body: some View {
    HStack {
      VStack {
        Grid(
          [
            [Text("Module"), Text("State")],
            [Text("Git"), Text("ok").foreground(.success)],
            [Text("Claude Code"), Text("busy").foreground(.warning)],
            [Text("Linear"), Text("off").foreground(.muted)],
          ], header: true, border: true, columnSeparators: true)
        HStack {
          Text("Gauge ")
          Gauge(Double(model.spinnerFrame % 100) / 100).frame(width: .exactly(20))
        }
        HStack {
          Text("Spinner ")
          Spinner(frame: model.spinnerFrame).foreground(.accent)
        }
        Paragraph(
          "This paragraph wraps to the available width. Resize the terminal and it reflows; "
            + "the tree is rebuilt in Swift and laid out by FTXUI."
        )
        .border(.light, title: "paragraph")
      }
      .frame(width: .exactly(40))
      ScrollView("gallery.log", state: model.log) {
        for line in model.logLines { Text(line) }
      }
      .focusPanel("gallery.log", title: model.log.followsEnd ? "Log (following; a adds)" : "Log")
      .flex()
    }
  }
}

extension View {
  /// A rounded border that lights up while `id` (or something inside it) has focus.
  fileprivate func focusPanel(_ id: FocusID, title: String) -> some View {
    ContextReader { context in
      self.border(.rounded, title: title, color: context.containsFocus(id) ? .focus : .border)
    }
  }
}
