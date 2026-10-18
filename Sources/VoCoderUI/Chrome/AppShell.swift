// The app's persistent frame (DESIGN §3.1, ADR 0008): `AppShell` wires the core, the keyboard,
// modals and toasts together; `AppChrome` draws the tab bar, the selected tab, the voice and hint
// bars, toasts, modals and the keyboard overlays. The `vocoder` executable and tests set it up
// the same way.
import VoCoderCore

@MainActor
public final class AppShell {
  public let core: AppCore
  public let host: UIHost
  public let keyboard: KeyboardController
  public let modals: ModalPresenter
  public let toasts: ToastCenter
  public let home: HomeTab
  private let log = Log(category: "shell")

  /// Loads `modules` with the built-in Home tab and connects the keyboard, modals and toasts to
  /// the dispatcher. `quit` stops the app (the terminal session).
  public init(
    modules: [any VoCoderModule.Type], environment: ModuleEnvironment,
    host: UIHost = UIHost(), overrides: KeyBindingOverrides = KeyBindingOverrides(),
    quit: @escaping @MainActor @Sendable () -> Void
  ) {
    let state = AppState()
    let home = HomeTab(state: state)
    var environment = environment
    environment.services.uiHost = host
    let core = AppCore(
      loaded: ModuleLoader.load(modules, environment: environment), environment: environment,
      state: state, builtInTabs: [home.factory])
    let toasts = ToastCenter()
    let modals = ModalPresenter(host: host, toasts: toasts)
    let keyboard = KeyboardController(
      host: host, dispatcher: core.dispatcher, overrides: overrides, quit: quit)
    core.dispatcher.registerBuiltIns(ModalCommands.make(for: modals))
    keyboard.rebuildKeymap()
    core.dispatcher.prompter = modals
    core.dispatcher.confirmer = modals
    keyboard.onFailure = { [weak toasts] message in toasts?.show(Notice(message, kind: .error)) }
    host.setContent {
      AppChrome(state: core.state, keyboard: keyboard, modals: modals, toasts: toasts)
    }
    self.core = core
    self.host = host
    self.keyboard = keyboard
    self.modals = modals
    self.toasts = toasts
    self.home = home
  }

  /// Opens the tabs, starts listening to attention sources and renders.
  public func start() {
    core.start()
    host.render()
    let issues = core.state.issues.count
    if issues > 0 {
      toasts.show(
        Notice("\(issues) problem\(issues == 1 ? "" : "s") loading modules: see Home", kind: .error)
      )
    }
    log.info("shell started")
  }

  /// Answers open modals (as cancelled) and closes the tabs.
  public func stop() {
    modals.cancelAll()
    core.stop()
    log.info("shell stopped")
  }
}

/// The frame: tab bar, selected tab, voice bar, hint bar; toasts, modals and keyboard overlays
/// on top.
public struct AppChrome: View {
  let state: AppState
  let keyboard: KeyboardController
  let modals: ModalPresenter
  let toasts: ToastCenter

  public init(
    state: AppState, keyboard: KeyboardController, modals: ModalPresenter,
    toasts: ToastCenter
  ) {
    self.state = state
    self.keyboard = keyboard
    self.modals = modals
    self.toasts = toasts
  }

  public var body: some View {
    ZStack {
      VStack {
        TabBarView(state: state)
        Divider()
        if let tab = state.selectedTab {
          TabContent(tab).flex()
        } else {
          Text("No tabs are open.").foreground(.muted).centered().flex()
        }
        Divider()
        VoiceBarView(state: state)
        HintBarView(keyboard: keyboard)
      }
      VStack {
        Spacer().frame(height: .exactly(2))
        ToastsView(center: toasts).flex()
        Spacer().frame(height: .exactly(4))
      }
      ModalsView(presenter: modals)
    }
    .commandOverlays(keyboard)
  }
}
