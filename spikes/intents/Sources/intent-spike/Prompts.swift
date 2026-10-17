import Foundation
import FoundationModels

enum PromptVariant: String, CaseIterable, Sendable {
  case plain  // catalog only
  case fewshot  // + examples
  case context  // + examples + app context injected into the prompt
  case tools  // + examples; context reachable only through tools (findTab, findIssue)
  case v2  // tuned after the first matrix: voice phrases, revised rules, context injected
}

struct AppContext: Codable, Sendable {
  struct Issue: Codable, Sendable { let key: String; let title: String }
  let tabs: [String]
  let focusedTab: String
  let focusedKind: String
  let agentState: String
  let currentIssue: String
  let issues: [Issue]
  let changedFiles: [String]
}

func catalogText() -> String {
  catalog.map { c in
    let slots = c.slots.isEmpty ? "" : " (slots: \(c.slots.joined(separator: ", ")))"
    return "- \(c.kind): \(c.summary)\(slots)"
  }.joined(separator: "\n")
}

func exampleText() -> String {
  var lines: [String] = []
  for c in catalog {
    for e in c.examples {
      let slot = c.slots.first.map { s -> String in
        switch (c.kind, s) {
        case ("switchTab", _): return e.contains("API") ? " tab=api" : " tab=2"
        case ("askAgent", _): return " text=\"run the tests\""
        case ("showDiff", _): return " file=main.swift"
        case ("setIssueStatus", _): return " issue=ENG-12 status=done"
        case ("commentOnIssue", _): return " issue=ENG-12 text=\"shipped\""
        case ("searchDocs", _): return " query=deploys"
        case ("agenda", _): return " day=today"
        default: return " \(s)=ENG-12"
        }
      } ?? ""
      lines.append("\"\(e)\" → \(c.kind)\(slot)")
    }
  }
  lines += [
    "\"add retry logic to the uploader\" → dictation text=\"add retry logic to the uploader\"",
    "\"next let's clean up the logging\" → dictation (\"next\" here is not a navigation command)",
    "\"do that\" → unclear (no clear referent)",
    "\"ticket\" → unclear",
  ]
  return lines.joined(separator: "\n")
}

func catalogTextV2() -> String {
  catalog.map { c in
    let slots = c.slots.isEmpty ? "" : " (slots: \(c.slots.joined(separator: ", ")))"
    let phrases = c.phrases.isEmpty ? "" : " Said as: \(c.phrases)."
    return "- \(c.kind): \(c.summary)\(slots)\(phrases)"
  }.joined(separator: "\n")
}

func instructionsV2() -> String {
  """
  You route spoken requests in VoCoder, a voice-controlled developer workspace with tabs for \
  code repos (each with a coding agent called Claude), tasks, docs and a calendar. Map the \
  user's utterance to exactly one command. The utterance comes from speech recognition and \
  may be informal.

  Commands:
  \(catalogTextV2())

  Rules:
  - A command is a request to VoCoder itself. Anything describing work on code (write, fix, \
  refactor, test, explain, build, commit, open a pull request) is dictation, even when it starts \
  with a word like next, open, stop, approve or close.
  - approve and deny only answer the agent's pending permission request.
  - Choose the command a colleague would understand. Choose unclear only when the utterance has \
  no reasonable reading, such as a bare filler word or "it" with nothing it could refer to.
  - Use the context to resolve tab names, "this ticket" and file names.
  - Fill only the slots the chosen command uses.

  Examples:
  \(exampleText())
  """
}

func instructions(_ v: PromptVariant) -> String {
  if v == .v2 { return instructionsV2() }
  var s = """
    You route spoken requests in VoCoder, a voice-controlled developer workspace with tabs for \
    code repos (each with a coding agent called Claude), tasks, docs and a calendar. Map the \
    user's utterance to exactly one command. The utterance comes from speech recognition and \
    may be informal or contain recognition errors.

    Commands:
    \(catalogText())

    Rules:
    - Only choose a command when the user clearly asks VoCoder to do it.
    - Requests about code (write, fix, explain, refactor, test) are dictation for the agent.
    - If the utterance is too vague to act on, choose unclear. Never guess for approve, deny, \
    setIssueStatus, commentOnIssue or startWorkingOn.
    - Issue keys look like ENG-123. Spoken forms like "eng one twenty three" mean ENG-123.
    - Fill only the slots the command uses. Copy free text without rephrasing.
    """
  if v != .plain {
    s += "\n\nExamples:\n\(exampleText())"
  }
  if v == .tools {
    s += """
      \n\nUse findTab to resolve a tab name, and findIssue to resolve an issue described by \
      words rather than a key. Don't call tools when the utterance is unambiguous.
      """
  }
  return s
}

func prompt(_ text: String, variant: PromptVariant, context: AppContext) -> String {
  guard variant == .context || variant == .v2 else { return "Utterance: \"\(text)\"" }
  let issues = context.issues.map { "\($0.key) \($0.title)" }.joined(separator: "; ")
  return """
    Context:
    - Open tabs: \(context.tabs.joined(separator: ", "))
    - Focused tab: \(context.focusedTab) (\(context.focusedKind)); agent is \(context.agentState)
    - Current issue: \(context.currentIssue)
    - Known issues: \(issues)
    - Changed files: \(context.changedFiles.joined(separator: ", "))

    Utterance: "\(text)"
    """
}

// MARK: - Tools

final class ToolLog: @unchecked Sendable {
  private let lock = NSLock()
  private var calls: [String] = []
  func add(_ s: String) { lock.withLock { calls.append(s) } }
  func drain() -> [String] { lock.withLock { defer { calls = [] }; return calls } }
}

struct FindTab: Tool {
  let context: AppContext
  let log: ToolLog
  let description = "Find open tabs whose name matches a spoken description"
  @Generable struct Arguments {
    @Guide(description: "Spoken tab name or description") var query: String
  }
  func call(arguments: Arguments) async throws -> String {
    log.add("findTab(\(arguments.query))")
    return "Open tabs: \(context.tabs.joined(separator: ", ")). Focused: \(context.focusedTab)."
  }
}

struct FindIssue: Tool {
  let context: AppContext
  let log: ToolLog
  let description = "Find tracker issues matching words from their title, or the current issue"
  @Generable struct Arguments {
    @Guide(description: "Words describing the issue, or 'current'") var query: String
  }
  func call(arguments: Arguments) async throws -> String {
    log.add("findIssue(\(arguments.query))")
    let words = Set(arguments.query.lowercased().split(separator: " ").map(String.init))
    let hits = context.issues.filter { i in
      !words.isDisjoint(with: i.title.lowercased().split(separator: " ").map(String.init))
    }
    let current = "Current issue: \(context.currentIssue)."
    if hits.isEmpty { return "No matching issues. \(current)" }
    return hits.map { "\($0.key): \($0.title)" }.joined(separator: "\n") + "\n\(current)"
  }
}
