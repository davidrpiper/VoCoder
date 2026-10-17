import Foundation
import FoundationModels

// intent-spike check
// intent-spike intents --schema a|b --prompt plain|fewshot|context|tools [--prewarm] [--stream]
//                      [--permissive] [--repeat N] [--only 1,2,3] [--label NAME]
// intent-spike summarise [--permissive] [--label NAME]
// intent-spike overflow

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let resultsDir = root.appending(path: "results")
let fixturesDir = root.deletingLastPathComponent().appending(path: "claude-code/fixtures")

func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

struct ResultFile<R: Encodable, C: Encodable>: Encodable { let config: C; let rows: R; let date: String }

func writeResult<R: Encodable, C: Encodable>(name: String, rows: R, cfg: C, summary: String) throws {
  let enc = JSONEncoder()
  enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  let date = ISO8601DateFormatter().string(from: Date())
  try enc.encode(ResultFile(config: cfg, rows: rows, date: date)).write(to: resultsDir.appending(path: "\(name).json"))
  try summary.write(to: resultsDir.appending(path: "\(name).md"), atomically: true, encoding: .utf8)
}

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func flag(_ f: String) -> Bool {
  if let i = args.firstIndex(of: f) { args.remove(at: i); return true }
  return false
}
@MainActor func option(_ f: String) -> String? {
  guard let i = args.firstIndex(of: f), i + 1 < args.count else { return nil }
  defer { args.removeSubrange(i...(i + 1)) }
  return args[i + 1]
}

let model = SystemLanguageModel.default
guard let cmd = args.first else {
  err("usage: intent-spike check | intents … | summarise … | overflow"); exit(2)
}
args.removeFirst()
if cmd == "turns" {
  // Prints the digests the summariser sees; needs no model.
  for (name, i) in selectedTurns {
    let t = try loadTurns(fixtures: fixturesDir, name: name)[i]
    print("=== \(name)#\(i)\n\(digest(t))\n--- claude spoken: \(t.spoken ?? "–")\n")
  }
  exit(0)
}
if cmd == "selftest" {
  // Scoring sanity checks; needs no model.
  let u = { (e: [String], s: [String: String]) in
    Utterance(id: 0, text: "", category: "", expect: e, slots: s, resolve: nil)
  }
  let cases: [(Utterance, Parsed, Bool)] = [
    (u(["switchTab"], ["tab": "3"]), Parsed(kind: "switchTab", slots: ["tab": "three"]), true),
    (u(["switchTab"], ["tab": "web-app"]), Parsed(kind: "switchTab", slots: ["tab": "Web App"]), true),
    (u(["switchTab"], ["tab": "5"]), Parsed(kind: "switchTab", slots: ["tab": "tab 5"]), true),
    (u(["openIssue"], ["issue": "ENG-142"]), Parsed(kind: "openIssue", slots: ["issue": "eng-142"]), true),
    (u(["openIssue"], ["issue": "ENG-142"]), Parsed(kind: "openIssue", slots: ["issue": "ENG-42"]), false),
    (u(["showDiff"], ["file": "authservice"]), Parsed(kind: "showDiff", slots: ["file": "Sources/Auth/AuthService.swift"]), true),
    (u(["commentOnIssue"], ["issue": "*", "text": "looks good to me"]), Parsed(kind: "commentOnIssue", slots: ["text": "Looks good to me!"]), true),
    (u(["askAgent", "dictation"], ["text": "x y"]), Parsed(kind: "dictation", slots: [:]), true),
    (u(["unclear"], [:]), Parsed(kind: "approve", slots: [:]), false),
  ]
  let norms = [
    ("pull up ticket eng one forty two", "pull up ticket ENG-142"),
    ("go to issue E N G one two three", "go to issue ENG-123"),
    ("pull up ticket eng ninety eight", "pull up ticket ENG-98"),
    ("open eng dash one hundred twenty three now", "open ENG-123 now"),
    ("open ENG-77", "open ENG-77"),
    ("the engine is one two three", "the engine is one two three"),
  ]
  var bad = 0
  for (a, b) in norms where normaliseIssueKeys(a) != b {
    print("normalise: \(a) → \(normaliseIssueKeys(a)), want \(b)"); bad += 1
  }
  for (i, (utt, p, want)) in cases.enumerated() where score(utt, p).slots != want {
    print("selftest case \(i) failed"); bad += 1
  }
  print(bad == 0 ? "selftest ok (\(cases.count) cases)" : "selftest: \(bad) failed")
  exit(bad == 0 ? 0 : 1)
}
if cmd == "check" {
  print("availability: \(model.availability)  contextSize: \(model.contextSize)")
  exit(model.isAvailable ? 0 : 1)
}
guard model.isAvailable else {
  err("model unavailable: \(model.availability)"); exit(1)
}

switch cmd {
case "intents":
  let cfg = RunConfig(
    schema: option("--schema") ?? "b", prompt: option("--prompt") ?? "context",
    prewarm: flag("--prewarm"), stream: flag("--stream"), permissive: flag("--permissive"),
    normalise: flag("--normalise"), repeatCount: Int(option("--repeat") ?? "1") ?? 1,
    only: option("--only")?.split(separator: ",").compactMap { Int($0) })
  let label = option("--label") ?? "\(cfg.schema)-\(cfg.prompt)\(cfg.prewarm ? "-prewarm" : "")\(cfg.stream ? "-stream" : "")\(cfg.normalise ? "-norm" : "")"
  let data = try Data(contentsOf: root.appending(path: "utterances.json"))
  let file = try JSONDecoder().decode(UtteranceFile.self, from: data)
  try await runIntents(cfg, file: file, label: label)
case "summarise":
  let permissive = flag("--permissive"), v2 = flag("--v2")
  let label = option("--label") ?? ((permissive ? "permissive" : "default") + (v2 ? "-v2" : ""))
  try await runSummaries(fixtures: fixturesDir, permissive: permissive, v2: v2, label: label)
case "overflow":
  try await runOverflow(fixtures: fixturesDir)
default:
  err("unknown command \(cmd)"); exit(2)
}
