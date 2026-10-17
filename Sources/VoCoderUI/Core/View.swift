// The view DSL (DESIGN §4.2): views are plain structs built from `@MainActor` view models; their
// bodies compose built-in views, which lower to the bridge's immutable node tree.
import VoCoderUIBridge

/// A piece of UI. Implement `body` by composing other views; there is no view-local state —
/// state lives in `@Observable` view models, and the host re-renders when they change.
@MainActor
public protocol View {
  associatedtype Body: View
  @ViewBuilder var body: Body { get }
}

extension Never: View {
  // `return` opts out of the result builder the requirement declares.
  public var body: Never { return fatalError("Never has no body") }
}

/// Built-in views lower themselves to nodes instead of having a body.
extension View where Body == Never {
  public var body: Never { return fatalError("\(Self.self) is a built-in view and has no body") }
}

/// Implemented by built-in views. Internal so the node vocabulary stays an implementation detail.
@MainActor
protocol PrimitiveView: View where Body == Never {
  func makeNodes(in context: RenderContext) -> [VCNode]
}

@MainActor
@resultBuilder
public enum ViewBuilder {
  public static func buildExpression(_ view: some View) -> [any View] { [view] }
  public static func buildBlock(_ parts: [any View]...) -> [any View] { parts.flatMap { $0 } }
  public static func buildOptional(_ part: [any View]?) -> [any View] { part ?? [] }
  public static func buildEither(first part: [any View]) -> [any View] { part }
  public static func buildEither(second part: [any View]) -> [any View] { part }
  public static func buildArray(_ parts: [[any View]]) -> [any View] { parts.flatMap { $0 } }
  public static func buildLimitedAvailability(_ part: [any View]) -> [any View] { part }
  public static func buildFinalResult(_ parts: [any View]) -> ViewGroup { ViewGroup(parts) }
}

/// Several views side by side in whatever container holds them (the result of a `@ViewBuilder`).
public struct ViewGroup: View, PrimitiveView {
  public typealias Body = Never
  let views: [any View]

  public init(_ views: [any View]) { self.views = views }
  public init(@ViewBuilder _ content: () -> ViewGroup) { self = content() }

  func makeNodes(in context: RenderContext) -> [VCNode] {
    views.flatMap { context.nodes(for: $0) }
  }
}

/// Nothing. Useful as a placeholder in conditionals.
public struct EmptyView: View, PrimitiveView {
  public typealias Body = Never
  public init() {}
  func makeNodes(in context: RenderContext) -> [VCNode] { [] }
}
