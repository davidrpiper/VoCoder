// The composition root's module list (DESIGN §4.10): the only place that names concrete module
// types. Adding an integration means adding its module here (and its target in Package.swift).
import ClaudeCodeModule
import DemoModule
import EventKitCalendarModule
import GitModule
import LinearModule
import NotionModule
import VoCoderCore

@MainActor
enum CompiledModules {
  /// Real modules, in tab order within each placement.
  static let all: [any VoCoderModule.Type] = [
    GitModule.self,
    ClaudeCodeModule.self,
    EventKitCalendarModule.self,
    LinearModule.self,
    NotionModule.self,
  ]

  /// `vocoder --demo`: fake-backed modules only, no accounts or network.
  static let demo: [any VoCoderModule.Type] = [DemoModule.self]

  /// Every compiled-in module: their ids are the config's module sections.
  static var known: [any VoCoderModule.Type] { all + demo }

  static func named(_ id: String) -> (any VoCoderModule.Type)? {
    known.first { $0.id.rawValue == id }
  }
}
