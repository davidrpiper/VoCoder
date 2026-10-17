import Foundation
import FoundationModels

// Turns from the P0-04 transcripts become a compact digest, which the on-device model turns into
// a speakable summary. Claude's own <spoken> line (when present) is the reference.

struct Turn: Sendable {
  let fixture: String
  let index: Int
  let request: String
  var actions: [String] = []
  var texts: [String] = []
  var spoken: String?
}

func loadJSONLines(_ url: URL) throws -> [[String: Any]] {
  try String(contentsOf: url, encoding: .utf8).split(separator: "\n").compactMap {
    try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
  }
}

func extractSpoken(_ s: String) -> (String, String?) {
  guard let r = s.range(of: "<spoken>"), let e = s.range(of: "</spoken>", range: r.upperBound..<s.endIndex)
  else { return (s, nil) }
  let spoken = String(s[r.upperBound..<e.lowerBound])
  let rest = (String(s[..<r.lowerBound]) + String(s[e.upperBound...])).trimmingCharacters(in: .whitespacesAndNewlines)
  return (rest, spoken)
}

func loadTurns(fixtures: URL, name: String) throws -> [Turn] {
  let input = try loadJSONLines(fixtures.appending(path: "\(name).in.ndjson"))
  let output = try loadJSONLines(fixtures.appending(path: "\(name).out.ndjson"))
  var prompts: [String] = []
  var decisions: [String: String] = [:]  // permission request_id → behavior
  for m in input {
    if m["type"] as? String == "user", let msg = m["message"] as? [String: Any], let c = msg["content"] as? String {
      prompts.append(c)
    }
    if m["type"] as? String == "control_response", let r = m["response"] as? [String: Any],
      let id = r["request_id"] as? String, let d = r["response"] as? [String: Any]
    {
      decisions[id] = d["behavior"] as? String
    }
  }
  var turns: [Turn] = []
  var cur: Turn?
  var toolNames: [String: String] = [:]
  func ensure() {
    if cur == nil { cur = Turn(fixture: name, index: turns.count, request: turns.count < prompts.count ? prompts[turns.count] : "?") }
  }
  for e in output {
    switch e["type"] as? String {
    case "assistant":
      ensure()
      let content = (e["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
      for c in content {
        if c["type"] as? String == "text", let t = c["text"] as? String {
          let (rest, spoken) = extractSpoken(t)
          if !rest.isEmpty { cur!.texts.append(rest) }
          if let spoken { cur!.spoken = spoken }
        } else if c["type"] as? String == "tool_use", let n = c["name"] as? String {
          let input = c["input"] as? [String: Any] ?? [:]
          let arg = (input["command"] ?? input["file_path"] ?? input["subject"] ?? input["status"]) as? String ?? ""
          toolNames[c["id"] as? String ?? ""] = n
          cur!.actions.append("\(n) \(arg.replacingOccurrences(of: "/REPO/\(name)/", with: ""))")
        }
      }
    case "control_request":
      ensure()
      if let r = e["request"] as? [String: Any], r["subtype"] as? String == "can_use_tool" {
        let id = e["request_id"] as? String ?? ""
        cur!.actions.append("(asked the user for permission to use \(r["tool_name"] ?? "?"): \(decisions[id] == "allow" ? "approved" : "denied"))")
      }
    case "user":
      ensure()
      let content = (e["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
      for c in content where c["type"] as? String == "tool_result" {
        var text = (c["content"] as? String) ?? ""
        if text.isEmpty, let arr = c["content"] as? [[String: Any]] { text = arr.compactMap { $0["text"] as? String }.joined() }
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        let err = (c["is_error"] as? Bool) == true ? " [error]" : ""
        cur!.actions.append("  → \(first.prefix(100))\(err)")
      }
    case "result":
      if let c = cur { turns.append(c) } else { ensure(); turns.append(cur!) }
      cur = nil
    default: break
    }
  }
  return turns
}

/// v2 pre-processing: replace content that can't be spoken (code, tables) by a short note and
/// drop markdown markers, so the model has nothing to copy verbatim.
func speakable(_ text: String) -> String {
  var out: [String] = []
  var inCode = false, tableRows = 0
  func flushTable() {
    if tableRows > 0 { out.append("(a table with \(max(tableRows - 2, 1)) rows)"); tableRows = 0 }
  }
  for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
    let l = line.trimmingCharacters(in: .whitespaces)
    if l.hasPrefix("```") {
      if !inCode { flushTable(); out.append("(a code block)") }
      inCode.toggle(); continue
    }
    if inCode { continue }
    if l.hasPrefix("|") { tableRows += 1; continue }
    flushTable()
    var t = l
    while t.hasPrefix("#") { t.removeFirst() }
    t = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
    out.append(t.trimmingCharacters(in: .whitespaces))
  }
  flushTable()
  return out.joined(separator: "\n")
}

@Generable
struct Spoken {
  @Guide(description: "One or two short spoken sentences, at most 30 words, no markdown")
  var sentences: String
}

func digest(_ t: Turn, v2: Bool = false) -> String {
  if v2 {
    var s = "User request: \(t.request)\n"
    if !t.actions.isEmpty { s += "Agent actions:\n" + t.actions.map { "- \($0)" }.joined(separator: "\n") + "\n" }
    return s + "Agent reply:\n" + speakable(t.texts.joined(separator: "\n\n"))
  }
  return digestV1(t)
}

func digestV1(_ t: Turn) -> String {
  var s = "User request: \(t.request)\n"
  if !t.actions.isEmpty { s += "Agent actions:\n" + t.actions.map { "- \($0)" }.joined(separator: "\n") + "\n" }
  s += "Agent reply:\n" + t.texts.joined(separator: "\n\n")
  return s
}

let summaryInstructions = """
  You turn one turn of a coding agent's work into a short summary that is spoken aloud to a \
  developer who cannot see the screen. Use one or two plain sentences, at most 30 words. No \
  markdown, code, symbols or file paths; say file names naturally. Say what the agent did and \
  the outcome, and mention anything that needs the user's attention.
  """

let selectedTurns: [(String, Int)] = [
  ("spoken-sonnet", 0),  // read README
  ("spoken-sonnet", 4),  // write notes.txt, two permission prompts
  ("spoken-sonnet", 5),  // long markdown explanation (process vs thread)
  ("spoken-sonnet", 6),  // git log via Bash
  ("spoken-sonnet", 9),  // markdown table
  ("spoken-sonnet", 11),  // session summary (long list)
  ("spoken-sonnet", 14),  // typo check, no change
  ("permission-host", 1),  // rm denied by the user
  ("todos", 0),  // task tools
]

struct SummaryRow: Codable, Sendable {
  let turn: String
  let request: String
  let promptTokens: Int?
  let summary: String?
  let error: String?
  let latencyMs: Double
  let words: Int
  let claudeSpoken: String?
}

@MainActor
func runSummaries(fixtures: URL, permissive: Bool, v2: Bool, label: String) async throws {
  let model = SystemLanguageModel(useCase: .general, guardrails: permissive ? .permissiveContentTransformations : .default)
  var cache: [String: [Turn]] = [:]
  var rows: [SummaryRow] = []
  for (name, i) in selectedTurns {
    if cache[name] == nil { cache[name] = try loadTurns(fixtures: fixtures, name: name) }
    let t = cache[name]![i]
    let d = digest(t, v2: v2)
    let tokens = try? await model.tokenCount(for: Prompt(d))
    let session = LanguageModelSession(model: model, instructions: summaryInstructions)
    let clock = ContinuousClock(), start = clock.now
    var summary: String?, failure: String?
    do {
      if v2 {
        let opts = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 90)
        summary = try await session.respond(to: d, generating: Spoken.self, options: opts).content.sentences
      } else {
        summary = try await session.respond(to: d, options: GenerationOptions(samplingMode: .greedy)).content
      }
    } catch { failure = describe(error) }
    let lat = ms(clock.now - start)
    let row = SummaryRow(
      turn: "\(name)#\(i)", request: t.request, promptTokens: tokens, summary: summary, error: failure,
      latencyMs: lat, words: summary.map { words($0).count } ?? 0, claudeSpoken: t.spoken)
    rows.append(row)
    err(String(format: "%@ %5.0fms %4@tok  %@", row.turn, lat, tokens.map { "\($0)" } ?? "?", summary ?? failure ?? ""))
  }
  var out = "### \(label)\n\nguardrails=\(permissive ? "permissiveContentTransformations" : "default") v2=\(v2)\n\n"
  out += "| Turn | Request | Prompt tok | ms | Words | On-device summary | Claude `<spoken>` |\n|---|---|---|---|---|---|---|\n"
  for r in rows {
    let cell = { (s: String) in s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|") }
    out += "| \(r.turn) | \(cell(String(r.request.prefix(60)))) | \(r.promptTokens.map(String.init) ?? "?") | \(Int(r.latencyMs)) | \(r.words) | \(cell(r.summary ?? "**\(r.error ?? "")**")) | \(cell(r.claudeSpoken ?? "–")) |\n"
  }
  let lat = rows.filter { $0.error == nil }.map(\.latencyMs)
  out += String(format: "\nLatency p50 / max: %.0f / %.0f ms. Errors: %d.\n", percentile(lat, 0.5), lat.max() ?? 0, rows.filter { $0.error != nil }.count)
  print(out)
  try writeResult(name: "summaries-\(label)", rows: rows, cfg: ["permissive": permissive, "v2": v2], summary: out)
}

// Context window: what happens past 4096 tokens, and how long until we find out.
@MainActor
func runOverflow(fixtures: URL) async throws {
  let model = SystemLanguageModel.default
  let turns = try loadTurns(fixtures: fixtures, name: "spoken-sonnet")
  let all = turns.map { digest($0) }.joined(separator: "\n\n")
  var out = "### overflow\n\ncontextSize=\(model.contextSize)\n\n| Input | Prompt tok | Result | ms |\n|---|---|---|---|\n"
  for copies in [1, 2, 3] {
    let text = Array(repeating: all, count: copies).joined(separator: "\n\n")
    let tokens = try? await model.tokenCount(for: Prompt(text))
    let session = LanguageModelSession(model: model, instructions: summaryInstructions)
    let clock = ContinuousClock(), start = clock.now
    var result: String
    do {
      let r = try await session.respond(to: text, options: GenerationOptions(samplingMode: .greedy))
      result = "ok: \(r.content.prefix(80))"
    } catch { result = describe(error) }
    let lat = ms(clock.now - start)
    err("x\(copies) \(tokens ?? -1) tok → \(result) (\(Int(lat)) ms)")
    out += "| whole session digest ×\(copies) | \(tokens.map(String.init) ?? "?") | \(result.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|")) | \(Int(lat)) |\n"
  }
  print(out)
  try writeResult(name: "overflow", rows: [String](), cfg: [String: String](), summary: out)
}
