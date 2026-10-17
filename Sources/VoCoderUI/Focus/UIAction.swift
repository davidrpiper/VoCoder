/// Generic actions the focused view and its enclosing scopes respond to, innermost first (a
/// responder chain along the focus path). Voice ("next", "open") and keys map onto these, so
/// every list, panel and dialog behaves the same way.
public enum UIAction: String, Sendable, CaseIterable {
  case moveUp, moveDown, moveLeft, moveRight
  case pageUp, pageDown
  case moveToFirst, moveToLast
  /// Open / choose the focused thing (Enter).
  case activate
  /// Back out: close, dismiss, leave a field (Esc).
  case cancel
  /// Handled by the focus manager, not by responders.
  case focusNext, focusPrevious
}

/// Handles an action for a focused view or scope; returns whether it did.
public typealias ActionHandler = @MainActor (UIAction) -> Bool

/// Key name (as `VCKeyDecoder` normalises it) → action.
///
/// **Temporary (ADR 0005):** P1-05 replaces this with registered commands (`list.next`, …)
/// whose key bindings come from the keymap and config; they dispatch the same actions.
public struct KeyMap: Sendable, Equatable {
  public var bindings: [String: UIAction]

  public init(_ bindings: [String: UIAction]) { self.bindings = bindings }

  public subscript(key: String) -> UIAction? { bindings[key] }

  public static let defaultBindings = KeyMap([
    "ArrowUp": .moveUp, "k": .moveUp,
    "ArrowDown": .moveDown, "j": .moveDown,
    "ArrowLeft": .moveLeft,
    "ArrowRight": .moveRight,
    "PageUp": .pageUp, "Ctrl-u": .pageUp,
    "PageDown": .pageDown, "Ctrl-d": .pageDown,
    "Home": .moveToFirst, "g": .moveToFirst,
    "End": .moveToLast, "G": .moveToLast,
    "Enter": .activate,
    "Esc": .cancel,
    "Tab": .focusNext,
    "Shift-Tab": .focusPrevious,
  ])
}
