import Testing
import VoCoderUI

// Placeholder until P1-03 adds the DSL and its snapshot tests. Bridge tests live in
// VoCoderUIBridgeTests.
@Suite struct VoCoderUITests {
  @Test func moduleLinks() {
    _ = VoCoderUI.self
  }
}
