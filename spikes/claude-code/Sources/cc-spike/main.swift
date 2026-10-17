import Foundation

// Usage:
//   cc-spike run <scenario|all> [--model haiku] [--work DIR]
//   cc-spike mcp-permission --socket PATH     (spawned by Claude Code as an MCP server)
//   cc-spike scrub <fixtures-dir> --work DIR  (re-apply scrubbing to saved fixtures)
//   cc-spike catalog <fixtures-dir>           (event schema table from saved transcripts)

let args = CommandLine.arguments
func flag(_ name: String) -> String? {
  args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
}

switch args.dropFirst().first {
case "mcp-permission":
  runMCPPermissionServer(socketPath: flag("--socket")!)

case "scrub":
  // Re-scrub saved fixtures in place: cc-spike scrub <dir> --work <work-dir>
  let work = URL(filePath: flag("--work")!)
  let env = Env(work: work, fixtures: URL(filePath: args[2]), model: "", selfPath: "")
  for f in (try FileManager.default.contentsOfDirectory(at: env.fixtures, includingPropertiesForKeys: nil)) where f.pathExtension == "ndjson" {
    try scrubText(String(contentsOf: f, encoding: .utf8), env.scrub).write(to: f, atomically: true, encoding: .utf8)
  }

case "catalog":
  catalog(URL(filePath: args[2]))

case "run":
  let name = args[2]
  let package = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let work = URL(filePath: flag("--work") ?? NSTemporaryDirectory() + "cc-spike")
  try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
  let fixtures = package.appending(path: "fixtures")
  let results = package.appending(path: "results")
  try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
  let model = flag("--model") ?? "haiku"
  let selfPath = URL(filePath: args[0]).standardizedFileURL.path(percentEncoded: false)
  for (scenario, body) in Scenarios.all where name == "all" || name == scenario {
    var env = Env(work: work, fixtures: fixtures, model: model, selfPath: selfPath)
    env.say("== \(scenario) (\(model)) \(Date.now.formatted(.iso8601))")
    let t0 = ContinuousClock.now
    do {
      try await body(&env)
    } catch {
      env.say("!! failed: \(error)")
    }
    env.say("== \(scenario) done in \((ContinuousClock.now - t0).ms) ms\n")
    let suffix = scenario == "spoken" ? "-\(model)" : ""
    try env.report.joined(separator: "\n").write(
      to: results.appending(path: "\(scenario)\(suffix).txt"), atomically: true, encoding: .utf8)
  }

default:
  log("usage: cc-spike run <scenario|all> [--model M] | mcp-permission --socket P | catalog DIR")
  exit(2)
}

/// Prints every (type, subtype) seen in `*.out.ndjson` with count and union of top-level keys.
func catalog(_ dir: URL) {
  var seen: [String: (count: Int, keys: Set<String>, files: Set<String>)] = [:]
  let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
  for f in files where f.lastPathComponent.hasSuffix(".out.ndjson") {
    let text = (try? String(contentsOf: f, encoding: .utf8)) ?? ""
    for line in text.split(separator: "\n") {
      guard let e = try? JSON.parse(String(line)) else { continue }
      var key = e["type"]?.string ?? "?"
      if let sub = e["subtype"]?.string { key += "/" + sub }
      if key == "control_request" { key += "/" + (e["request"]?["subtype"]?.string ?? "?") }
      if key == "stream_event" { key += "/" + (e["event"]?["type"]?.string ?? "?") }
      if key == "assistant" || key == "user" {
        let blocks = (e["message"]?["content"]?.array ?? []).compactMap { $0["type"]?.string }
        key += "[" + (blocks.isEmpty ? "string" : Set(blocks).sorted().joined(separator: ",")) + "]"
      }
      var entry = seen[key] ?? (0, [], [])
      entry.count += 1
      entry.keys.formUnion(e.object?.keys ?? [:].keys)
      entry.files.insert(String(f.lastPathComponent.dropLast(".out.ndjson".count)))
      seen[key] = entry
    }
  }
  for (k, v) in seen.sorted(by: { $0.key < $1.key }) {
    print("\(k)\t\(v.count)\t\(v.keys.sorted().joined(separator: ","))\t\(v.files.sorted().prefix(4).joined(separator: ","))")
  }
}
