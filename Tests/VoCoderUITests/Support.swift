import VoCoderUI
import VoCoderUIBridge

extension UIHost {
  /// Feeds raw terminal bytes through the bridge's parser, delivering events synchronously.
  func type(_ input: String) {
    renderer.onEvent = { [self] event in MainActor.assumeIsolated { self.handle(event) } }
    renderer.injectInput(input)
    renderIfNeeded()
  }

  func plain(width: Int, height: Int = 0) -> String {
    renderIfNeeded()
    return renderer.renderToString(width: width, height: height, ansi: false)
  }
}

/// Lines joined by "\n" with a trailing newline, as plain renders produce.
func lines(_ rows: String...) -> String {
  rows.map { $0 + "\n" }.joined()
}

/// Renders a view once, without a host the test keeps.
@MainActor
func render(_ view: some View, width: Int, height: Int = 0, theme: Theme = .dark) -> String {
  let host = UIHost(theme: theme) { view }
  return host.plain(width: width, height: height)
}
