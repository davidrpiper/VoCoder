import Foundation
import Observation
import VoCoderCore
import VoCoderUIBridge

/// Connects a root view to a renderer: renders it (again whenever an `@Observable` value it
/// read changes), keeps focus in sync, and routes bridge events — keys through the key map to
/// the focus path's action handlers, widget edits to their views. The run loop, signals and
/// chrome belong to the app (P1-07).
@MainActor
public final class UIHost {
  public let renderer: VCRenderer
  public let focus = FocusManager()
  public var theme: Theme {
    didSet { if theme != oldValue { invalidate() } }
  }
  /// Temporary until P1-05 (ADR 0005).
  public var keyMap = KeyMap.defaultBindings
  /// Keys that map to no action or that no handler took (P1-05: the command keymap).
  public var onUnhandledKey: (@MainActor (String) -> Bool)?
  public var onResize: (@MainActor (_ width: Int, _ height: Int) -> Void)?
  public private(set) var size = (width: 0, height: 0)
  /// Set by `invalidate()`; a render is scheduled on the main actor.
  public private(set) var needsRender = true
  public private(set) var renderCount = 0

  private let content: @MainActor () -> any View
  private var widgetHandlers: [String: WidgetHandlers] = [:]
  private var renderScheduled = false
  private let log = Log(category: "ui")

  public init<Content: View>(
    renderer: VCRenderer = VCRenderer(), theme: Theme = .automatic(),
    content: @escaping @MainActor () -> Content
  ) {
    self.renderer = renderer
    self.theme = theme
    self.content = { content() }
    focus.onChange = { [weak self] in
      self?.syncFocusedWidget()
      self?.invalidate()
    }
  }

  /// Delivers the renderer's events to this host on the main actor, in order.
  public func connect() {
    renderer.onEvent = { [weak self] event in
      DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
    }
  }

  // MARK: Rendering

  /// Asks for a render soon; several requests coalesce into one.
  public func invalidate() {
    needsRender = true
    guard !renderScheduled else { return }
    renderScheduled = true
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        self.renderScheduled = false
        self.renderIfNeeded()
      }
    }
  }

  public func renderIfNeeded() {
    if needsRender { render() }
  }

  /// Renders now. Focus is reconciled with the new tree; if that moves it, the tree is built
  /// again so focus styling matches (at most twice more).
  public func render() {
    needsRender = false
    for pass in 0..<3 {
      let context = RenderContext(theme: theme, focus: focus, renderer: renderer)
      let root = withObservationTracking {
        context.node(for: content())
      } onChange: { [weak self] in
        // Called synchronously by the mutation (normally on the main actor), before the change.
        if Thread.isMainThread {
          MainActor.assumeIsolated { self?.invalidate() }
        } else {
          DispatchQueue.main.async { MainActor.assumeIsolated { self?.invalidate() } }
        }
      }
      for id in context.focusTree.duplicates {
        log.error("duplicate focus id \(id) in one render; only the first is focusable")
      }
      let before = focus.focused
      focus.update(context.focusTree.tree)
      if focus.focused == before || pass == 2 {
        widgetHandlers = context.widgetHandlers
        renderer.setRoot(root)
        syncFocusedWidget()
        renderCount += 1
        return
      }
    }
  }

  private func syncFocusedWidget() {
    let widget = focus.focusedWidget
    if renderer.focusedWidget != widget { renderer.focusedWidget = widget }
  }

  // MARK: Events

  public func handle(_ event: VCEvent) {
    switch event.kind {
    case .key:
      handleKey(event.key)
    case .widgetChanged:
      if let id = event.widgetId { widgetHandlers[id]?.onChange?(event.stringValue ?? "") }
    case .widgetSubmitted:
      if let id = event.widgetId { widgetHandlers[id]?.onSubmit?(event.stringValue ?? "") }
    case .resize:
      size = (event.width, event.height)
      onResize?(event.width, event.height)
    case .mouse:
      break
    @unknown default:
      break
    }
  }

  /// A key as the bridge names it. Returns whether anything handled it.
  @discardableResult
  public func handleKey(_ key: String) -> Bool {
    if let action = keyMap[key], perform(action) { return true }
    return onUnhandledKey?(key) ?? false
  }

  /// Sends an action along the focus path, innermost first. Returns whether it was handled.
  @discardableResult
  public func perform(_ action: UIAction) -> Bool {
    switch action {
    case .focusNext: return focus.focusNext()
    case .focusPrevious: return focus.focusPrevious()
    default:
      for handler in focus.handlerChain where handler(action) {
        // Handlers may change bridge state (scroll offsets) that observation doesn't see.
        invalidate()
        return true
      }
      return false
    }
  }

  // MARK: Widgets

  public func text(of field: FocusID) -> String {
    renderer.stringValue(forWidget: field.rawValue) ?? ""
  }

  /// Sets a text field's text (cursor to the end). Works before it is first rendered.
  public func setText(_ text: String, for field: FocusID) {
    renderer.setStringValue(text, forWidget: field.rawValue)
    invalidate()
  }
}
