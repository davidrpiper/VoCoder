import Foundation
import FoundationModels

struct Utterance: Codable, Sendable {
  let id: Int
  let text: String
  let category: String
  let expect: [String]
  let slots: [String: String]?
  let resolve: [String: String]?
}

struct UtteranceFile: Codable, Sendable {
  let context: AppContext
  let utterances: [Utterance]
}

enum Schema: String, Sendable { case a, b, c }

struct RunConfig: Sendable, Codable {
  var schema: String
  var prompt: String
  var prewarm: Bool
  var stream: Bool
  var permissive: Bool
  var normalise: Bool
  var repeatCount: Int
  var only: [Int]?
}

struct Row: Codable, Sendable {
  let id: Int
  let run: Int
  let text: String
  let category: String
  let expect: [String]
  let got: Parsed?
  let error: String?
  let kindOK: Bool
  let slotsOK: Bool
  let dangerous: Bool
  let latencyMs: Double
  let firstKindMs: Double?
  let tools: [String]
}

let riskyKinds: Set<String> = [
  "approve", "deny", "setIssueStatus", "commentOnIssue", "startWorkingOn", "interruptAgent",
]

// MARK: - Scoring

func norm(_ s: String) -> String {
  String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
}

let numberWords = [
  "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
  "eight": "8", "nine": "9",
]

func tabNorm(_ s: String) -> String {
  var n = norm(s)
  if n.hasPrefix("tab") { n.removeFirst(3) }
  if n.hasPrefix("number") { n.removeFirst(6) }
  return numberWords[n] ?? n
}

func words(_ s: String) -> [String] {
  s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
}

func slotMatches(_ name: String, expected: String, got: String?) -> Bool {
  if expected == "*" { return true }
  guard let got, !got.isEmpty else { return false }
  switch name {
  case "tab": return tabNorm(got) == tabNorm(expected)
  case "issue": return norm(got) == norm(expected)
  case "file": return norm(got).contains(norm(expected))
  default:
    let e = words(expected), g = Set(words(got))
    guard !e.isEmpty else { return true }
    return Double(e.filter(g.contains).count) / Double(e.count) >= 0.6
  }
}

func score(_ u: Utterance, _ p: Parsed?) -> (kind: Bool, slots: Bool, dangerous: Bool) {
  guard let p else { return (false, false, false) }
  let kindOK = u.expect.contains(p.kind)
  // Slots are only checked when the preferred kind was chosen (alternatives have other slots).
  var slotsOK = kindOK
  if kindOK, p.kind == u.expect[0] {
    for (k, v) in u.slots ?? [:] where !slotMatches(k, expected: v, got: p.slots[k]) {
      slotsOK = false
    }
  }
  return (kindOK, slotsOK, !kindOK && riskyKinds.contains(p.kind))
}

// MARK: - Running

func describe(_ error: any Error) -> String {
  if let e = error as? LanguageModelSession.GenerationError {
    switch e {
    case .exceededContextWindowSize: return "exceededContextWindowSize"
    case .guardrailViolation: return "guardrailViolation"
    case .refusal: return "refusal"
    case .decodingFailure: return "decodingFailure"
    case .unsupportedGuide: return "unsupportedGuide"
    case .assetsUnavailable: return "assetsUnavailable"
    case .rateLimited: return "rateLimited"
    case .concurrentRequests: return "concurrentRequests"
    case .unsupportedLanguageOrLocale: return "unsupportedLanguageOrLocale"
    @unknown default: return "generationError: \(e)"
    }
  }
  return "\(error)"
}

func ms(_ d: Duration) -> Double {
  Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

@MainActor
func parseOnce(
  _ u: Utterance, schema: Schema, variant: PromptVariant, context: AppContext,
  prewarm: Bool, stream: Bool, normalise: Bool, model: SystemLanguageModel, log: ToolLog
) async -> (Parsed?, String?, Double, Double?) {
  let tools: [any Tool] =
    variant == .tools ? [FindTab(context: context, log: log), FindIssue(context: context, log: log)] : []
  let session = LanguageModelSession(model: model, tools: tools, instructions: instructions(variant))
  if prewarm {
    // Simulates prewarming at push-to-talk press; the user is still speaking for a while.
    session.prewarm()
    try? await Task.sleep(for: .milliseconds(1500))
  }
  let text = prompt(normalise ? normaliseIssueKeys(u.text) : u.text, variant: variant, context: context)
  let options = GenerationOptions(samplingMode: .greedy)
  let clock = ContinuousClock()
  let start = clock.now
  do {
    switch schema {
    case .a:
      let r = try await session.respond(to: text, generating: ParseA.self, options: options)
      return (r.content.parsed, nil, ms(clock.now - start), nil)
    case .c:
      let r = try await session.respond(to: text, generating: ParseC.self, options: options)
      return (r.content.parsed, nil, ms(clock.now - start), nil)
    case .b:
      if stream {
        var firstKind: Double?
        var last: ParseB.PartiallyGenerated?
        for try await snap in session.streamResponse(to: text, generating: ParseB.self, options: options) {
          // A simple enum only appears in a snapshot once it is complete.
          if firstKind == nil, snap.content.kind != nil { firstKind = ms(clock.now - start) }
          last = snap.content
        }
        let total = ms(clock.now - start)
        guard let l = last, let kind = l.kind else { return (nil, "incomplete", total, firstKind) }
        var s: [String: String] = [:]
        s["tab"] = l.tab; s["issue"] = l.issue; s["status"] = l.status; s["text"] = l.text
        s["file"] = l.file; s["query"] = l.query; s["day"] = l.day
        return (Parsed(kind: "\(kind)", slots: s, confidence: l.confidence), nil, total, firstKind)
      }
      let r = try await session.respond(to: text, generating: ParseB.self, options: options)
      return (r.content.parsed, nil, ms(clock.now - start), nil)
    }
  } catch {
    return (nil, describe(error), ms(clock.now - start), nil)
  }
}

@MainActor
func runIntents(_ cfg: RunConfig, file: UtteranceFile, label: String) async throws {
  let schema = Schema(rawValue: cfg.schema)!
  let variant = PromptVariant(rawValue: cfg.prompt)!
  let model = SystemLanguageModel(
    useCase: .general, guardrails: cfg.permissive ? .permissiveContentTransformations : .default)
  let utterances = file.utterances.filter { cfg.only?.contains($0.id) ?? true }
  let log = ToolLog()
  var rows: [Row] = []

  let instrTokens = try? await model.tokenCount(for: Instructions(instructions(variant)))
  err("instructions: \(instrTokens.map(String.init) ?? "?") tokens")

  for run in 1...cfg.repeatCount {
    for u in utterances {
      let (p, e, lat, fk) = await parseOnce(
        u, schema: schema, variant: variant, context: file.context, prewarm: cfg.prewarm,
        stream: cfg.stream, normalise: cfg.normalise, model: model, log: log)
      let s = score(u, p)
      let row = Row(
        id: u.id, run: run, text: u.text, category: u.category, expect: u.expect, got: p, error: e,
        kindOK: s.kind, slotsOK: s.slots, dangerous: s.dangerous, latencyMs: lat, firstKindMs: fk,
        tools: log.drain())
      rows.append(row)
      let mark = s.slots ? "✓" : (s.kind ? "~" : (s.dangerous ? "✗!" : "✗"))
      let got = p.map { "\($0.kind) \($0.slots.filter { !$0.value.isEmpty }) c=\($0.confidence.map { String(format: "%.2f", $0) } ?? "-")" } ?? e ?? "?"
      err(String(format: "%@ %2d %5.0fms  %@  ← %@ %@", mark, u.id, lat, got, u.text, row.tools.isEmpty ? "" : "\(row.tools)"))
    }
  }
  let summary = summarize(rows, cfg: cfg, label: label, instructionTokens: instrTokens)
  print(summary)
  try writeResult(name: "intents-\(label)", rows: rows, cfg: cfg, summary: summary)
}

func pct(_ n: Int, _ d: Int) -> String { d == 0 ? "-" : String(format: "%.0f%%", 100 * Double(n) / Double(d)) }

func percentile(_ xs: [Double], _ p: Double) -> Double {
  guard !xs.isEmpty else { return .nan }
  let s = xs.sorted()
  return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
}

func summarize(_ rows: [Row], cfg: RunConfig, label: String, instructionTokens: Int?) -> String {
  let n = rows.count
  // The first call in a process includes model load; report it separately.
  let lat = rows.dropFirst().map(\.latencyMs)
  var out = "### \(label)\n\n"
  out += "schema=\(cfg.schema) prompt=\(cfg.prompt) prewarm=\(cfg.prewarm) stream=\(cfg.stream) "
  out += "permissive=\(cfg.permissive) normalise=\(cfg.normalise) runs=\(cfg.repeatCount) n=\(n) instructionTokens=\(instructionTokens.map(String.init) ?? "?")\n\n"
  out += "| Metric | Value |\n|---|---|\n"
  out += "| Kind accuracy | \(pct(rows.filter(\.kindOK).count, n)) |\n"
  out += "| Kind + slots | \(pct(rows.filter(\.slotsOK).count, n)) |\n"
  out += "| Dangerous errors (risky kind chosen wrongly) | \(rows.filter(\.dangerous).count) |\n"
  out += "| Errors thrown | \(rows.filter { $0.error != nil }.count) |\n"
  out += String(format: "| First call (incl. load) | %.0f ms |\n", rows.first?.latencyMs ?? 0)
  out += String(format: "| Latency p50 / p95 / max (rest) | %.0f / %.0f / %.0f ms |\n", percentile(lat, 0.5), percentile(lat, 0.95), lat.max() ?? 0)
  let fk = rows.compactMap(\.firstKindMs)
  if !fk.isEmpty {
    out += String(format: "| Kind known (stream) p50 / p95 | %.0f / %.0f ms |\n", percentile(fk, 0.5), percentile(fk, 0.95))
  }
  let toolRows = rows.filter { !$0.tools.isEmpty }
  if cfg.prompt == "tools" { out += "| Rows with tool calls | \(toolRows.count) |\n" }
  // Tuning set (ids 1-60) vs hold-out (61+, never used to tune v2)
  let wrongAction = { (r: Row) in !r.kindOK && r.got != nil && r.got?.kind != "unclear" }
  out += "\n| Set | n | kind | kind+slots | wrong action (not unclear) | dangerous |\n|---|---|---|---|---|---|\n"
  for (name, rs) in [("tuning 1–60", rows.filter { $0.id <= 60 }), ("hold-out 61+", rows.filter { $0.id > 60 }), ("all", rows)] where !rs.isEmpty {
    out += "| \(name) | \(rs.count) | \(pct(rs.filter(\.kindOK).count, rs.count)) | \(pct(rs.filter(\.slotsOK).count, rs.count)) | \(rs.filter(wrongAction).count) | \(rs.filter(\.dangerous).count) |\n"
  }
  // Per category
  out += "\n| Category | n | kind | kind+slots |\n|---|---|---|---|\n"
  for c in Set(rows.map(\.category)).sorted() {
    let r = rows.filter { $0.category == c }
    out += "| \(c) | \(r.count) | \(pct(r.filter(\.kindOK).count, r.count)) | \(pct(r.filter(\.slotsOK).count, r.count)) |\n"
  }
  // Calibration
  out += "\n| Confidence | n | kind correct |\n|---|---|---|\n"
  for (lo, hi) in [(0.0, 0.5), (0.5, 0.8), (0.8, 0.95), (0.95, 1.01)] {
    let r = rows.filter { ($0.got?.confidence).map { $0 >= lo && $0 < hi } ?? false }
    out += String(format: "| [%.2f, %.2f) | %d | %@ |\n", lo, min(hi, 1), r.count, pct(r.filter(\.kindOK).count, r.count))
  }
  // Repeat stability
  if cfg.repeatCount > 1 {
    let byID = Dictionary(grouping: rows, by: \.id)
    let unstable = byID.values.filter { Set($0.map { $0.got?.kind ?? "error" }).count > 1 }.count
    out += "\nUnstable utterances across runs: \(unstable) of \(byID.count)\n"
  }
  let failures = rows.filter { !$0.slotsOK }
  if !failures.isEmpty {
    out += "\nFailures:\n"
    for f in failures {
      let got = f.got.map { "\($0.kind) \($0.slots.filter { !$0.value.isEmpty })" } ?? f.error ?? "?"
      out += "- \(f.id) \"\(f.text)\" → \(got) (expected \(f.expect.joined(separator: "|")))\(f.dangerous ? " **dangerous**" : "")\n"
    }
  }
  return out
}
