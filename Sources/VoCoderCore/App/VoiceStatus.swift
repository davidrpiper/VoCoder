// What the voice bar shows (DESIGN §3.1): mic state, the live partial transcript and what is
// being spoken. The chrome draws it from `AppState.voice`; the voice layer sets it (Phase 2).

public struct VoiceStatus: Sendable, Equatable {
  public enum Mic: Sendable, Equatable, CaseIterable {
    /// No voice input (not set up yet, or turned off).
    case off
    case idle
    case listening
    /// Recognising / routing an utterance.
    case thinking
    case speaking
  }

  public var mic: Mic
  /// The partial (or last) transcript.
  public var transcript: String
  /// What is being said right now.
  public var speaking: String

  public init(mic: Mic = .off, transcript: String = "", speaking: String = "") {
    self.mic = mic
    self.transcript = transcript
    self.speaking = speaking
  }
}
