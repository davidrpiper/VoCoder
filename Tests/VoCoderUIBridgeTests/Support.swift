import Synchronization
import VoCoderUIBridge

/// Renders `node` off-screen through a fresh renderer.
func render(_ node: VCNode, width: Int = 20, height: Int = 0) -> String {
  let renderer = VCRenderer()
  renderer.setRoot(node)
  return renderer.renderToString(width: width, height: height, ansi: false)
}

/// Lines joined by "\n" with a trailing newline, as `renderToString` produces plain text.
func lines(_ rows: String...) -> String {
  rows.map { $0 + "\n" }.joined()
}

/// Collects events delivered by a renderer.
final class EventRecorder: Sendable {
  private let storage = Mutex<[VCEvent]>([])

  init(_ renderer: VCRenderer) {
    renderer.onEvent = { [self] event in self.storage.withLock { $0.append(event) } }
  }

  var events: [VCEvent] { storage.withLock { $0 } }
  var keys: [String] { events.filter { $0.kind == .key }.map(\.key) }
  func reset() { storage.withLock { $0.removeAll() } }
}

/// Removes ANSI escape sequences and carriage returns, and trims trailing spaces per line.
func stripANSI(_ text: String) -> String {
  var out = ""
  var iterator = text.unicodeScalars.makeIterator()
  while let scalar = iterator.next() {
    if scalar == "\u{1B}" {
      // CSI: ESC [ params final(0x40–0x7E)
      guard iterator.next() == "[" else { continue }
      while let c = iterator.next(), !(0x40...0x7E).contains(c.value) {}
    } else if scalar != "\r" {
      out.unicodeScalars.append(scalar)
    }
  }
  return out.split(separator: "\n", omittingEmptySubsequences: false)
    .map { line in String(line.reversed().drop(while: { $0 == " " }).reversed()) }
    .joined(separator: "\n")
}
