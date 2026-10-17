import FoundationModels

// The command catalog stands in for the command registry: P2-05 generates the intent schema and
// the prompt text from registered commands, so the prompt here is generated from this table too.

struct CommandSpec: Sendable {
  let kind: String
  let summary: String
  let slots: [String]
  let examples: [String]
  var phrases: String = ""  // voice phrases the command registers (v2 prompt only)
}

let catalog: [CommandSpec] = [
  .init(kind: "switchTab", summary: "Go to a tab by name, alias or number.", slots: ["tab"],
        examples: ["go to the API", "tab two"], phrases: "go to, switch to, open <tab>, show me <tab>; tabs include Home, Tasks, Docs, Calendar and repos"),
  .init(kind: "nextTab", summary: "Go to the next tab.", slots: [], examples: ["next tab"], phrases: "next tab, tab to the right"),
  .init(kind: "previousTab", summary: "Go to the previous tab.", slots: [], examples: ["previous tab"], phrases: "previous tab, go back a tab"),
  .init(kind: "whereAmI", summary: "Say which tab and item is focused.", slots: [],
        examples: ["where am I"], phrases: "where am I, what tab is this, what's focused"),
  .init(kind: "repeatLast", summary: "Repeat the last thing VoCoder said.", slots: [],
        examples: ["say that again"], phrases: "say that again, pardon, what was that"),
  .init(kind: "askAgent", summary: "Explicitly address the coding agent (Claude) with a prompt.",
        slots: ["text"], examples: ["tell Claude to run the tests"], phrases: "tell Claude to…, ask the agent…"),
  .init(kind: "approve", summary: "Approve the agent's pending permission request.", slots: [],
        examples: ["approve", "allow it"], phrases: "approve, allow, yes do it, go ahead, let it run"),
  .init(kind: "deny", summary: "Deny the agent's pending permission request.", slots: [],
        examples: ["deny", "don't allow that"], phrases: "deny, reject, don't allow, block it"),
  .init(kind: "interruptAgent", summary: "Stop the agent's current turn.", slots: [],
        examples: ["interrupt Claude"], phrases: "stop/cancel/kill/abort the agent or what it is doing"),
  .init(kind: "readLastResponse", summary: "Read out the agent's last response.", slots: [],
        examples: ["what did it say"], phrases: "what did Claude say, read its answer, what is the agent doing"),
  .init(kind: "whatChanged", summary: "Summarise the repo's changed files (git status).", slots: [],
        examples: ["what changed"], phrases: "what changed, which files did it touch, anything modified"),
  .init(kind: "showDiff", summary: "Show the diff of a changed file.", slots: ["file"],
        examples: ["show the diff for main.swift"], phrases: "show the diff for <file>, changes in <file>"),
  .init(kind: "openIssue", summary: "Open a tracker issue.", slots: ["issue"],
        examples: ["open ENG-12"], phrases: "open/pull up/show <issue>"),
  .init(kind: "setIssueStatus", summary: "Change an issue's status.", slots: ["issue", "status"],
        examples: ["move ENG-12 to done"], phrases: "move/mark/set <issue> to <status>, close <issue>"),
  .init(kind: "commentOnIssue", summary: "Post a comment on an issue.", slots: ["issue", "text"],
        examples: ["comment on ENG-12: shipped"], phrases: "comment/reply/leave a note on <issue>: <text>"),
  .init(kind: "startWorkingOn", summary: "Start work on an issue (branch, status, agent).",
        slots: ["issue"], examples: ["start working on ENG-12"], phrases: "start working on/pick up <issue>"),
  .init(kind: "searchDocs", summary: "Search documentation pages.", slots: ["query"],
        examples: ["search the docs for deploys"], phrases: "search the docs for, find the page about"),
  .init(kind: "agenda", summary: "Read calendar events for a day.", slots: ["day"],
        examples: ["what's on today"], phrases: "what's on my calendar, meetings, schedule, what's next today"),
  .init(kind: "dictation", summary: "Not a command: content for the focused context, e.g. a prompt "
          + "for the agent in a repo tab.", slots: ["text"], examples: []),
  .init(kind: "unclear", summary: "Too vague or ambiguous to act on; VoCoder will ask back.",
        slots: [], examples: []),
]

let slotNames = ["tab", "issue", "status", "text", "file", "query", "day"]

// MARK: - Schema A: enum with associated values

@Generable
enum CommandA {
  case switchTab(tab: String)
  case nextTab
  case previousTab
  case whereAmI
  case repeatLast
  case askAgent(text: String)
  case approve
  case deny
  case interruptAgent
  case readLastResponse
  case whatChanged
  case showDiff(file: String)
  case openIssue(issue: String)
  case setIssueStatus(issue: String?, status: String)
  case commentOnIssue(issue: String?, text: String)
  case startWorkingOn(issue: String)
  case searchDocs(query: String)
  case agenda(day: String)
  case dictation(text: String)
  case unclear
}

@Generable
struct ParseA {
  var command: CommandA
  @Guide(description: "How sure you are that this is what the user meant, from 0 to 1",
         .range(0...1))
  var confidence: Double
}

// MARK: - Schema B: flat kind + optional slots

@Generable
enum KindB {
  case switchTab, nextTab, previousTab, whereAmI, repeatLast, askAgent, approve, deny
  case interruptAgent, readLastResponse, whatChanged, showDiff, openIssue, setIssueStatus
  case commentOnIssue, startWorkingOn, searchDocs, agenda, dictation, unclear
}

@Generable
struct ParseB {
  var kind: KindB
  @Guide(description: "Tab name or number, for switchTab") var tab: String?
  @Guide(description: "Issue key like ENG-123, for issue commands") var issue: String?
  @Guide(description: "Target status, for setIssueStatus") var status: String?
  @Guide(description: "Free text: prompt, comment or dictated content") var text: String?
  @Guide(description: "File name, for showDiff") var file: String?
  @Guide(description: "Search query, for searchDocs") var query: String?
  @Guide(description: "Day, for agenda") var day: String?
  @Guide(description: "How sure you are that this is what the user meant, from 0 to 1",
         .range(0...1))
  var confidence: Double
}

// MARK: - Schema C: B without the (uncalibrated) confidence field

@Generable
struct ParseC {
  var kind: KindB
  @Guide(description: "Tab name or number, for switchTab") var tab: String?
  @Guide(description: "Issue key like ENG-123, for issue commands") var issue: String?
  @Guide(description: "Target status, for setIssueStatus") var status: String?
  @Guide(description: "Free text: prompt, comment or dictated content") var text: String?
  @Guide(description: "File name, for showDiff") var file: String?
  @Guide(description: "Search query, for searchDocs") var query: String?
  @Guide(description: "Day, for agenda") var day: String?
}

// MARK: - Common result

struct Parsed: Sendable, Codable {
  var kind: String
  var slots: [String: String]
  var confidence: Double?
}

extension ParseA {
  var parsed: Parsed {
    var s: [String: String] = [:]
    let k: String
    switch command {
    case .switchTab(let tab): k = "switchTab"; s["tab"] = tab
    case .nextTab: k = "nextTab"
    case .previousTab: k = "previousTab"
    case .whereAmI: k = "whereAmI"
    case .repeatLast: k = "repeatLast"
    case .askAgent(let text): k = "askAgent"; s["text"] = text
    case .approve: k = "approve"
    case .deny: k = "deny"
    case .interruptAgent: k = "interruptAgent"
    case .readLastResponse: k = "readLastResponse"
    case .whatChanged: k = "whatChanged"
    case .showDiff(let file): k = "showDiff"; s["file"] = file
    case .openIssue(let issue): k = "openIssue"; s["issue"] = issue
    case .setIssueStatus(let issue, let status): k = "setIssueStatus"; s["issue"] = issue; s["status"] = status
    case .commentOnIssue(let issue, let text): k = "commentOnIssue"; s["issue"] = issue; s["text"] = text
    case .startWorkingOn(let issue): k = "startWorkingOn"; s["issue"] = issue
    case .searchDocs(let query): k = "searchDocs"; s["query"] = query
    case .agenda(let day): k = "agenda"; s["day"] = day
    case .dictation(let text): k = "dictation"; s["text"] = text
    case .unclear: k = "unclear"
    }
    return Parsed(kind: k, slots: s, confidence: confidence)
  }
}

extension ParseB {
  var parsed: Parsed {
    var s: [String: String] = [:]
    s["tab"] = tab; s["issue"] = issue; s["status"] = status; s["text"] = text
    s["file"] = file; s["query"] = query; s["day"] = day
    return Parsed(kind: "\(kind)", slots: s, confidence: confidence)
  }
}

extension ParseC {
  var parsed: Parsed {
    var s: [String: String] = [:]
    s["tab"] = tab; s["issue"] = issue; s["status"] = status; s["text"] = text
    s["file"] = file; s["query"] = query; s["day"] = day
    return Parsed(kind: "\(kind)", slots: s, confidence: nil)
  }
}
