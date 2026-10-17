/// Generic actions the focused view and its enclosing scopes respond to, innermost first (a
/// responder chain along the focus path). The navigation commands (`list.down`, `ui.activate`,
/// …) send these, whether from keys, the palette or voice, so every list, panel and dialog
/// behaves the same way.
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
