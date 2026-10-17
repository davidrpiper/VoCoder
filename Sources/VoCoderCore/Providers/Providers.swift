// Extension-point protocols for contributed services (DESIGN §4.10); agents are in `Agents/`.
// Seams whose work package hasn't started are declared with identity (and capabilities) only;
// their members arrive with that WP (calendar P3-03, trackers P4-01, docs P5-01, voice P2-xx).

/// A contributed service with a stable id, unique within its extension point.
public protocol Provider: Sendable {
  var id: ProviderID { get }
}

/// Optional tracker features; UI and commands degrade when one is missing.
public struct TaskTrackerCapabilities: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  /// Cycles (Linear) or sprints (Jira).
  public static let iterations = TaskTrackerCapabilities(rawValue: 1 << 0)
  public static let subtasks = TaskTrackerCapabilities(rawValue: 1 << 1)
}

/// An issue tracker (Linear; Jira later). DESIGN §4.5, P4-01.
public protocol TaskTracker: Provider {
  var capabilities: TaskTrackerCapabilities { get }
}

/// A docs source (Notion; Confluence later). DESIGN §4.5, P5-01.
public protocol DocsProvider: Provider {}

/// A calendar (EventKit). DESIGN §4.5, P3-03.
public protocol CalendarProvider: Provider {}

/// A chat service (Slack later). Declared so the seam exists; nothing uses it yet.
public protocol ChatProvider: Provider {}

/// A cross-app workflow composed from provider actions ("start working on …", P4-04).
public protocol Workflow: Sendable {
  var id: WorkflowID { get }
  var title: String { get }
}

/// A provider action exposed to the brain as a tool (P3-02).
public protocol BrainTool: Provider {}

/// Something that starts and stops listening: keyboard push-to-talk, AirPods, … (P2-04).
public protocol ActivationSource: Provider {}

/// Speech to text (P2-02).
public protocol SpeechRecognizer: Provider {}

/// Text to speech (P2-03).
public protocol SpeechSynthesizer: Provider {}
