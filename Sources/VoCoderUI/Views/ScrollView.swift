import Observation
import VoCoderUIBridge

/// Scroll state of a focusable `ScrollView`. The offset itself lives in the bridge.
@MainActor
@Observable
public final class ScrollState {
  /// Pinned to the bottom (streaming output). Scrolling up unpins; `moveToLast` re-pins.
  public var followsEnd: Bool
  public var pageSize: Int

  public init(followsEnd: Bool = false, pageSize: Int = 10) {
    self.followsEnd = followsEnd
    self.pageSize = pageSize
  }
}

/// A vertical viewport. A view marked `keepVisible()` inside stays visible. With a `state`, the
/// view is a focusable leaf that scrolls with the movement actions; `onAction` sees each action
/// first and may take it (return true).
public struct ScrollView: View, PrimitiveView {
  public typealias Body = Never
  let id: FocusID
  let state: ScrollState?
  let onAction: ActionHandler?
  let content: ViewGroup

  public init(
    _ id: FocusID, state: ScrollState? = nil, onAction: ActionHandler? = nil,
    @ViewBuilder content: () -> ViewGroup
  ) {
    self.id = id
    self.state = state
    self.onAction = onAction
    self.content = content()
  }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    let widgetId = id.rawValue
    if let state {
      let renderer = context.renderer
      context.focusTree.addLeaf(id, widgetId: nil) { [onAction] action in
        if onAction?(action) == true { return true }
        guard let renderer else { return false }
        return Self.scroll(renderer, widgetId, state, action)
      }
    }
    return [
      .scrollFrame(
        id: widgetId, followingEnd: state?.followsEnd ?? false,
        child: .vbox(context.nodes(for: content)))
    ]
  }

  private static func scroll(
    _ renderer: VCRenderer, _ widgetId: String, _ state: ScrollState, _ action: UIAction
  ) -> Bool {
    let stored = renderer.integerValue(forWidget: widgetId)
    let offset = stored == VCNoValue ? 0 : stored
    let target: Int
    switch action {
    case .moveUp: target = offset - 1
    case .moveDown: target = offset + 1
    case .pageUp: target = offset - state.pageSize
    case .pageDown: target = offset + state.pageSize
    case .moveToFirst: target = 0
    case .moveToLast:
      state.followsEnd = true
      return true
    default: return false
    }
    // The bridge clamps past-the-end offsets when it draws and writes the result back.
    state.followsEnd = false
    renderer.setIntegerValue(max(0, target), forWidget: widgetId)
    return true
  }
}
