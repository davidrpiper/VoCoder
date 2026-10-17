import Testing
import VoCoderVoice

// Placeholder until P2-01 adds the first voice tests.
@Suite struct VoCoderVoiceTests {
  @Test func targetLinks() {
    #expect(String(describing: VoCoderVoice.self) == "VoCoderVoice")
  }
}
