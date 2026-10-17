import Testing
import VoCoderUIBridge

// Placeholder until P1-03's snapshot tests: proves FTXUI renders off-screen through the bridge.
@Suite struct BridgeLinkTests {
  @Test func rendersTextOffScreen() {
    let rendered = VCBuildInfo.renderText("VoCoder", width: 10)
    #expect(rendered.hasPrefix("VoCoder"))
  }
}
