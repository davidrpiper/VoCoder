// Short-lived messages in the bottom-right corner (DESIGN §3.1): command failures, notices from
// commands (`CommandPrompter.notify`), startup problems. Each disappears after its duration.
import Observation
import VoCoderCore

@MainActor
@Observable
public final class ToastCenter {
  public struct Toast: Identifiable, Equatable {
    public let id: Int
    public let notice: Notice
  }

  /// Oldest first; at most `limit`.
  public private(set) var toasts: [Toast] = []
  public var limit = 3

  /// Waits a toast's lifetime; tests replace it to expire toasts on demand.
  @ObservationIgnored public var sleep: @Sendable (Duration) async throws -> Void = {
    try await Task.sleep(for: $0)
  }
  @ObservationIgnored private var nextID = 1
  @ObservationIgnored private let log = Log(category: "toasts")

  public init() {}

  /// Shows `notice` for `duration` (errors stay a little longer by default).
  public func show(_ notice: Notice, for duration: Duration? = nil) {
    let toast = Toast(id: nextID, notice: notice)
    nextID += 1
    toasts.append(toast)
    if toasts.count > limit { toasts.removeFirst(toasts.count - limit) }
    log.debug("toast \(toast.id)")
    let lifetime = duration ?? (notice.kind == .error ? .seconds(6) : .seconds(4))
    let sleep = sleep
    Task { [weak self] in
      try? await sleep(lifetime)
      self?.dismiss(toast.id)
    }
  }

  public func dismiss(_ id: Int) {
    toasts.removeAll { $0.id == id }
  }
}

/// The toasts, stacked at the bottom right of the space they are given.
struct ToastsView: View {
  let center: ToastCenter

  var body: some View {
    if !center.toasts.isEmpty {
      VStack {
        Spacer()
        for toast in center.toasts {
          HStack {
            Spacer()
            HStack {
              Text(Self.icon(toast.notice.kind) + " ").foreground(Self.color(toast.notice.kind))
              Text(toast.notice.message)
            }
            .border(.rounded, color: Self.color(toast.notice.kind))
            .frame(width: .atMost(50))
            .clearUnder()
            Text("  ")
          }
        }
      }
    }
  }

  static func icon(_ kind: Notice.Kind) -> String {
    switch kind {
    case .info: "i"
    case .success: "✓"
    case .error: "✗"
    }
  }

  static func color(_ kind: Notice.Kind) -> Color {
    switch kind {
    case .info: .info
    case .success: .success
    case .error: .danger
    }
  }
}
