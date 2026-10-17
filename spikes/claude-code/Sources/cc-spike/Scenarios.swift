import Foundation

@MainActor
struct Env {
  let work: URL
  let fixtures: URL
  let model: String
  let selfPath: String
  var report: [String] = []

  mutating func say(_ s: String) {
    print(s)
    fflush(stdout)
    report.append(s)
  }

  /// A fresh throwaway git repo per scenario.
  func makeRepo(_ name: String) throws -> URL {
    let dir = work.appending(path: "repos/\(name)")
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "# Spike repo\n\nThe project codename is BLUEBIRD.\n".write(
      to: dir.appending(path: "README.md"), atomically: true, encoding: .utf8)
    try shell("git init -q && git add . && git -c user.name=spike -c user.email=spike@example.com commit -qm init", in: dir)
    return dir
  }

  var scrub: [(String, String)] {
    let w = work.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return [
      ("/private/" + w + "/repos", "/REPO"), ("/" + w + "/repos", "/REPO"),
      ("/private/" + w, "/WORK"), ("/" + w, "/WORK"),
      (FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/")), "Users/USER"),
    ]
  }

  func options(_ repo: URL) -> ClaudeOptions {
    var o = ClaudeOptions(cwd: repo)
    o.model = model
    return o
  }
}

@discardableResult
func shell(_ cmd: String, in dir: URL) throws -> String {
  let p = Process()
  p.executableURL = URL(filePath: "/bin/sh")
  p.arguments = ["-c", cmd]
  p.currentDirectoryURL = dir
  let out = Pipe()
  p.standardOutput = out
  try p.run()
  p.waitUntilExit()
  return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

func toolUses(_ events: [JSON]) -> [String] {
  events.filter { $0["type"]?.string == "assistant" }.flatMap { e in
    (e["message"]?["content"]?.array ?? []).filter { $0["type"]?.string == "tool_use" }.map {
      "\($0["name"]?.string ?? "?")(\(($0["input"]?["command"] ?? $0["input"]?["file_path"] ?? "").string ?? ""))"
    }
  }
}

func toolResults(_ events: [JSON]) -> [String] {
  events.filter { $0["type"]?.string == "user" }.flatMap { e in
    (e["message"]?["content"]?.array ?? []).filter { $0["type"]?.string == "tool_result" }.map { r in
      let content = r["content"]?.string ?? r["content"]?.array?.compactMap { $0["text"]?.string }.joined() ?? ""
      return "\(r["is_error"]?.bool == true ? "ERR" : "ok"): \(content.prefix(120))"
    }
  }
}

func oneLine(_ s: String, _ n: Int = 160) -> String {
  String(s.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(n))
}

// MARK: - Scenarios

@MainActor
enum Scenarios {
  static let all: [(String, (inout Env) async throws -> Void)] = [
    ("multiturn", multiturn),
    ("permission-host", permissionHost),
    ("permission-mcp", permissionMCP),
    ("resume", resume),
    ("interrupt", interrupt),
    ("partial", partial),
    ("todos", todos),
    ("spoken", spoken),
  ]

  /// Three turns in one process, then two turns sent back to back (queueing).
  static func multiturn(_ env: inout Env) async throws {
    let s = Session(env.options(try env.makeRepo("multiturn")), name: "multiturn")
    let initResp = try await s.start()
    env.say("initialize response keys: \(initResp?["response"]?.object?.keys.sorted() ?? [])")
    for prompt in ["Reply with exactly: one", "What did you reply last time? One word.", "Reply with exactly: three"] {
      let r = try await s.turn(prompt)
      env.say("turn '\(prompt)' → '\(oneLine(r.text))' first-text \(r.firstTextMs ?? -1) ms, result \(r.latencyMs) ms, num_turns \(r.result["num_turns"]?.int ?? -1)")
    }
    // Back-to-back: second prompt written while the first is still running.
    let sent = s.now
    try await s.proc.send("Reply with exactly: alpha")
    try await s.proc.send("Reply with exactly: beta")
    let a = try await s.collect(sentAt: sent)
    let b = try await s.collect(sentAt: sent)
    env.say("queued: '\(oneLine(a.text))' (\(a.latencyMs) ms, queued_turn_count \(a.result["queued_turn_count"] ?? .null)), '\(oneLine(b.text))' (\(b.latencyMs) ms, queued_turn_count \(b.result["queued_turn_count"] ?? .null))")
    env.say("session \(s.sessionID ?? "?"), exit \(await s.finish(fixtures: env.fixtures, scrub: env.scrub).map(String.init) ?? "timeout")")
  }

  /// Host control protocol: allow, deny, allow with modified input, allow + "always" rule.
  static func permissionHost(_ env: inout Env) async throws {
    let repo = try env.makeRepo("permission-host")
    let s = Session(env.options(repo), name: "permission-host")
    _ = try await s.start()
    try await permissionTurns(s, repo: repo, env: &env)
    env.say("exit \(await s.finish(fixtures: env.fixtures, scrub: env.scrub).map(String.init) ?? "timeout")")
  }

  static func permissionTurns(_ s: Session, repo: URL, env: inout Env) async throws {
    func show(_ label: String, _ r: TurnResult, from: Int) {
      for p in s.permissions[from...] {
        let rtt = (p.request["tool_use_id"]?.string).flatMap { s.toolResultTimes[$0] }.map { "\(($0 - p.receivedAt).ms) ms" } ?? "?"
        env.say("  [\(label)] can_use_tool \(p.request["tool_name"]?.string ?? "?") input=\(oneLine(p.request["input"]?.line ?? "", 120)) → \(p.decision["behavior"]?.string ?? "?") (tool_result +\(rtt))")
        env.say("    request keys: \(p.request.object?.keys.sorted() ?? [])")
      }
      env.say("  [\(label)] tools: \(toolUses(r.events)) results: \(toolResults(r.events))")
      env.say("  [\(label)] reply: \(oneLine(r.text, 220)) (\(r.latencyMs) ms) permission_denials: \(oneLine(r.result["permission_denials"]?.line ?? "", 200))")
    }
    var n = s.permissions.count
    s.policy = { allow($0) }
    var r = try await s.turn("Use the Bash tool to run exactly this command: echo approved > a.txt")
    show("allow", r, from: n)
    env.say("  a.txt = \(oneLine((try? String(contentsOf: repo.appending(path: "a.txt"), encoding: .utf8)) ?? "<missing>"))")

    n = s.permissions.count
    s.policy = { _ in deny("The user declined this from VoCoder.") }
    r = try await s.turn("Use the Bash tool to run exactly this command: rm README.md. If it is refused, do not retry or work around it; just tell me.")
    show("deny", r, from: n)
    env.say("  README.md exists: \(FileManager.default.fileExists(atPath: repo.appending(path: "README.md").path(percentEncoded: false)))")

    n = s.permissions.count
    s.policy = { req in
      var input = req["input"]?.object ?? [:]
      if input["content"] != nil { input["content"] = "modified by VoCoder\n" }
      if input["command"] != nil { input["command"] = "echo modified-by-vocoder > b.txt" }
      return ["behavior": "allow", "updatedInput": .object(input)]
    }
    r = try await s.turn("Use the Write tool to create b.txt containing exactly: original")
    show("modify", r, from: n)
    env.say("  b.txt = \(oneLine((try? String(contentsOf: repo.appending(path: "b.txt"), encoding: .utf8)) ?? "<missing>"))")

    // "Always allow": echo back the suggestions as updatedPermissions, then repeat the command.
    n = s.permissions.count
    s.policy = { req in
      ["behavior": "allow", "updatedInput": req["input"] ?? [:], "updatedPermissions": req["permission_suggestions"] ?? []]
    }
    r = try await s.turn("Use the Bash tool to run exactly: echo one > c.txt")
    show("always", r, from: n)
    n = s.permissions.count
    s.policy = { _ in deny("should not have been asked") }
    r = try await s.turn("Use the Bash tool to run exactly the same command again: echo one > c.txt")
    show("always-repeat", r, from: n)
    env.say("  prompts on repeat: \(s.permissions.count - n)")
    env.say("  settings.local.json: \(oneLine((try? String(contentsOf: repo.appending(path: ".claude/settings.local.json"), encoding: .utf8)) ?? "<none>", 300))")

    // Session-scoped rule: rewrite every suggestion's destination to "session".
    try? FileManager.default.removeItem(at: repo.appending(path: ".claude"))
    n = s.permissions.count
    s.policy = { req in
      let suggestions = (req["permission_suggestions"]?.array ?? []).map { sug -> JSON in
        var o = sug.object ?? [:]
        o["destination"] = "session"
        return .object(o)
      }
      return ["behavior": "allow", "updatedInput": req["input"] ?? [:], "updatedPermissions": .array(suggestions)]
    }
    r = try await s.turn("Use the Bash tool to run exactly: touch d.txt")
    show("session", r, from: n)
    n = s.permissions.count
    s.policy = { _ in deny("should not have been asked") }
    r = try await s.turn("Use the Bash tool to run exactly the same command again: touch d.txt")
    show("session-repeat", r, from: n)
    env.say("  prompts on repeat: \(s.permissions.count - n); settings file written: \(FileManager.default.fileExists(atPath: repo.appending(path: ".claude/settings.local.json").path(percentEncoded: false)))")
  }

  /// Same allow/deny flow through the MCP permission tool.
  static func permissionMCP(_ env: inout Env) async throws {
    let repo = try env.makeRepo("permission-mcp")
    let socket = env.work.appending(path: "perm.sock").path(percentEncoded: false)
    let decisions = DecisionBox()
    try UnixSocket.serve(path: socket) { args in
      let d = decisions.policy(args)
      decisions.log(args, d)
      return d
    }
    let config: JSON = ["mcpServers": ["vocoder": ["command": .string(env.selfPath), "args": ["mcp-permission", "--socket", .string(socket)]]]]
    let configURL = env.work.appending(path: "mcp.json")
    try config.line.write(to: configURL, atomically: true, encoding: .utf8)
    var o = env.options(repo)
    o.permission = .mcp(configPath: configURL.path(percentEncoded: false), tool: "mcp__vocoder__approve")
    let s = Session(o, name: "permission-mcp")
    let started = s.now
    _ = try await s.start()
    for (label, policy, prompt) in [
      ("allow", { @Sendable (a: JSON) in allow(a) } as PermissionPolicy, "Use the Bash tool to run exactly this command: echo via-mcp > a.txt"),
      ("deny", { @Sendable _ in deny("Declined via MCP.") } as PermissionPolicy, "Use the Bash tool to run exactly: rm README.md. If refused, don't retry; tell me."),
    ] {
      decisions.policy = policy
      let before = decisions.count
      let r = try await s.turn(prompt)
      for (args, d) in decisions.entries[before...] {
        env.say("  [\(label)] mcp args keys=\(args.object?.keys.sorted() ?? []) tool=\(args["tool_name"]?.string ?? "?") → \(d["behavior"]?.string ?? "?")")
      }
      env.say("  [\(label)] tools: \(toolUses(r.events)) results: \(toolResults(r.events)) reply: \(oneLine(r.text)) (\(r.latencyMs) ms)")
    }
    env.say("  a.txt = \(oneLine((try? String(contentsOf: repo.appending(path: "a.txt"), encoding: .utf8)) ?? "<missing>")), README exists: \(FileManager.default.fileExists(atPath: repo.appending(path: "README.md").path(percentEncoded: false)))")
    env.say("  host can_use_tool requests seen (should be 0): \(s.permissions.count); startup \((s.now - started).ms) ms total")
    env.say("exit \(await s.finish(fixtures: env.fixtures, scrub: env.scrub).map(String.init) ?? "timeout")")
  }

  /// Kill the process, restart with --resume, check context survives.
  static func resume(_ env: inout Env) async throws {
    let repo = try env.makeRepo("resume")
    let s1 = Session(env.options(repo), name: "resume-1")
    _ = try await s1.start()
    _ = try await s1.turn("Remember the code word PINEAPPLE-42. Reply only: OK")
    let id = s1.sessionID!
    env.say("first session \(id), exit \(await s1.finish(fixtures: env.fixtures, scrub: env.scrub).map(String.init) ?? "timeout")")

    var o = env.options(repo)
    o.resume = id
    let s2 = Session(o, name: "resume-2")
    let t0 = s2.now
    _ = try await s2.start()
    let r = try await s2.turn("What was the code word? Reply with just the code word.")
    env.say("resumed: init session_id \(s2.sessionID ?? "?") (same: \(s2.sessionID == id)); reply '\(oneLine(r.text))' ok=\(r.text.contains("PINEAPPLE-42")); start→result \((s2.now - t0).ms) ms")
    env.say("result session_id \(r.result["session_id"]?.string ?? "?")")
    _ = await s2.finish(fixtures: env.fixtures, scrub: env.scrub)

    // Resume a session that was killed mid-turn (SIGKILL), as after a crash.
    let s3 = Session(env.options(repo), name: "resume-3-killed")
    _ = try await s3.start()
    _ = try await s3.turn("Remember the code word MANGO-7. Reply only: OK")
    try await s3.proc.send("Write a 400 word essay about mangoes.")
    try await Task.sleep(for: .seconds(2))
    await s3.proc.signal(SIGKILL)
    let id3 = s3.sessionID!
    _ = await s3.finish(fixtures: env.fixtures, scrub: env.scrub)
    var o4 = env.options(repo)
    o4.resume = id3
    let s4 = Session(o4, name: "resume-4-after-kill")
    _ = try await s4.start()
    let r4 = try await s4.turn("What was the code word? Reply with just the code word.")
    env.say("after SIGKILL mid-turn: reply '\(oneLine(r4.text))' ok=\(r4.text.contains("MANGO-7"))")
    _ = await s4.finish(fixtures: env.fixtures, scrub: env.scrub)

    // Unknown session id.
    var o5 = env.options(repo)
    o5.resume = UUID().uuidString.lowercased()
    let s5 = Session(o5, name: "resume-5-unknown")
    _ = try? await s5.start()
    let r5 = try? await s5.turn("hi")
    env.say("unknown id: result=\(oneLine(r5?.result.line ?? "<none>", 200)) exit=\(await s5.finish(fixtures: env.fixtures, scrub: env.scrub).map(String.init) ?? "timeout") stderr=\(oneLine(s5.proc.transcript.stderrText, 200))")
  }

  /// Control-protocol interrupt during a long tool call and during text streaming; SIGINT.
  static func interrupt(_ env: inout Env) async throws {
    let repo = try env.makeRepo("interrupt")
    var o = env.options(repo)
    o.partialMessages = true
    let s = Session(o, name: "interrupt")
    _ = try await s.start()

    // 1. During a long-running tool call.
    var fired: Duration?
    var interruptResponse: JSON?
    s.policy = { allow($0) }
    // Foreground `sleep N` is blocked by Claude Code (it pushes the model to background it), so
    // use a long-running python call; interrupt 3 s after the tool_use is announced.
    s.onEvent = { e in
      guard fired == nil, e["type"]?.string == "assistant",
        e["message"]?["content"]?.array?.contains(where: { $0["type"]?.string == "tool_use" }) == true
      else { return }
      fired = .zero
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(3))
        fired = s.now
        interruptResponse = try? await s.proc.control("interrupt")
      }
    }
    var sent = s.now
    try await s.proc.send("Use the Bash tool (foreground, not background) to run exactly: python3 -c 'import time; time.sleep(30); print(\"finished\")'")
    var r = try await s.collect(sentAt: sent)
    env.say("tool interrupt: response \(oneLine(interruptResponse?.line ?? "?", 200)); result subtype=\(r.result["subtype"]?.string ?? "?") is_error=\(r.result["is_error"] ?? .null) terminal_reason=\(r.result["terminal_reason"] ?? .null) stop_reason=\(r.result["stop_reason"] ?? .null); interrupt→result \(fired.map { (r.resultAt - $0).ms } ?? -1) ms; tool results \(toolResults(r.events))")

    // 2. During text streaming.
    fired = nil
    var deltas = 0
    s.onEvent = { e in
      if e["type"]?.string == "stream_event", e["event"]?["type"]?.string == "content_block_delta" {
        deltas += 1
        if deltas == 10, fired == nil {
          fired = s.now
          Task { @MainActor in interruptResponse = try? await s.proc.control("interrupt") }
        }
      }
    }
    sent = s.now
    try await s.proc.send("Write a 500 word story about a lighthouse. No tools.")
    r = try await s.collect(sentAt: sent)
    env.say("text interrupt: after \(deltas) deltas total; result subtype=\(r.result["subtype"]?.string ?? "?") is_error=\(r.result["is_error"] ?? .null) terminal_reason=\(r.result["terminal_reason"] ?? .null); interrupt→result \(fired.map { (r.resultAt - $0).ms } ?? -1) ms; text chars in assistant messages \(r.text.count)")
    s.onEvent = nil

    // 3. Process still usable?
    r = try await s.turn("Reply with exactly: still here")
    env.say("after interrupts: '\(oneLine(r.text))' (\(r.latencyMs) ms)")

    // 4. Interrupt while idle.
    let idle = try await s.proc.control("interrupt")
    env.say("idle interrupt response: \(oneLine(idle.line, 200))")

    // 5. SIGINT mid-turn.
    try await s.proc.send("Write a 500 word story about a fox. No tools.")
    try await Task.sleep(for: .seconds(2))
    let sig = s.now
    await s.proc.signal(SIGINT)
    let status = await s.proc.waitForExit(timeout: .seconds(10))
    env.say("SIGINT mid-turn: exit status \(status.map(String.init) ?? "still running after 10 s") after \((s.now - sig).ms) ms")
    _ = await s.finish(fixtures: env.fixtures, scrub: env.scrub)
  }

  /// --include-partial-messages with a tool call: fixture for streaming deltas.
  static func partial(_ env: inout Env) async throws {
    var o = env.options(try env.makeRepo("partial"))
    o.partialMessages = true
    let s = Session(o, name: "partial")
    _ = try await s.start()
    let r = try await s.turn("Read README.md, then tell me the project codename in one short sentence.")
    var kinds: [String: Int] = [:]
    for e in r.events where e["type"]?.string == "stream_event" {
      let k = (e["event"]?["type"]?.string ?? "?") + ((e["event"]?["delta"]?["type"]?.string).map { "/" + $0 } ?? "")
      kinds[k, default: 0] += 1
    }
    env.say("stream_event kinds: \(kinds.sorted { $0.key < $1.key })")
    env.say("first text \(r.firstTextMs ?? -1) ms (full assistant message), result \(r.latencyMs) ms; reply: \(oneLine(r.text))")
    _ = await s.finish(fixtures: env.fixtures, scrub: env.scrub)
  }

  /// Does any todo/task tool exist headless, and what do its events look like?
  static func todos(_ env: inout Env) async throws {
    var o = env.options(try env.makeRepo("todos"))
    // Task tools are not in the headless default set (TodoWrite doesn't exist); opt in explicitly.
    o.tools = "Bash,Read,Write,Edit,TaskCreate,TaskUpdate,TaskList,TaskGet"
    let s = Session(o, name: "todos")
    _ = try await s.start()
    s.policy = { allow($0) }
    let r = try await s.turn("Use your task tools to create a 3 item list (lint, test, ship), then mark lint in progress and test completed, then stop. Do not run anything else.")
    for e in r.events where e["type"]?.string == "user" {
      if let tur = e["tool_use_result"] { env.say("  tool_use_result: \(oneLine(tur.line, 220))") }
    }
    env.say("tools used: \(toolUses(r.events)); permissions asked: \(s.permissions.map { $0.request["tool_name"]?.string ?? "?" })")
    env.say("reply: \(oneLine(r.text, 300))")
    _ = await s.finish(fixtures: env.fixtures, scrub: env.scrub)
  }

  static let spokenInstruction = """
    You are running inside VoCoder, a voice-first terminal workspace. The user may be listening \
    rather than reading. End every reply with a short summary for text-to-speech inside \
    <spoken>...</spoken> tags: one or two plain sentences, at most 40 words, no markdown, no code, \
    no file paths or symbols. Put it last, after any other content.
    """

  static let spokenPrompts = [
    "What does README.md say? Read it.",
    "Write a Swift function that reverses a string. Just the code and a one-line note.",
    "What's 17 times 23?",
    "List three ideas for naming a CLI tool.",
    "Create notes.txt containing a haiku about git.",
    "Explain in detail the difference between a process and a thread.",
    "Run git log and tell me how many commits there are.",
    "Read the file does-not-exist.swift.",
    "Refactor nothing; just say whether this repo has tests.",
    "Give me a markdown table of 3 HTTP status codes and their meanings.",
    "ok",
    "Summarise everything we've done in this session.",
    "Write a bash one-liner that counts lines in all .md files.",
    "Is it safe to force-push to main? Short answer.",
    "Fix the typo in README.md if there is one.",
  ]

  /// `<spoken>` compliance across a multi-turn session with tools.
  static func spoken(_ env: inout Env) async throws {
    var o = env.options(try env.makeRepo("spoken-\(env.model)"))
    o.appendSystemPrompt = spokenInstruction
    let s = Session(o, name: "spoken-\(env.model)")
    _ = try await s.start()
    s.policy = { allow($0) }
    var ok = 0, last = 0, multi = 0, symbols = 0, words: [Int] = []
    var latencies: [Int] = []
    for p in spokenPrompts {
      let r = try await s.turn(p)
      latencies.append(r.latencyMs)
      // Only the final assistant text block counts (earlier ones precede tool calls).
      let matches = r.text.matches(of: /<spoken>([\s\S]*?)<\/spoken>/)
      if let m = matches.last {
        ok += 1
        if matches.count > 1 { multi += 1 }
        let body = String(m.1).trimmingCharacters(in: .whitespacesAndNewlines)
        if r.text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("</spoken>") { last += 1 }
        let w = body.split(whereSeparator: \.isWhitespace).count
        words.append(w)
        if body.contains(/[`*#|\/\\_<>\[\]{}]/) { symbols += 1 }
        env.say("  ✓ \(oneLine(p, 40)) → \(w) words: \(oneLine(body, 140))")
      } else {
        env.say("  ✗ \(oneLine(p, 40)) → no <spoken>: \(oneLine(r.text, 140))")
      }
    }
    words.sort()
    latencies.sort()
    env.say("spoken[\(env.model)]: present \(ok)/\(spokenPrompts.count), last \(last), multiple \(multi), with symbols \(symbols), words median \(words.isEmpty ? 0 : words[words.count / 2]) max \(words.last ?? 0); turn latency median \(latencies[latencies.count / 2]) ms")
    _ = await s.finish(fixtures: env.fixtures, scrub: env.scrub)
  }
}

/// Thread-safe holder for the MCP scenario's current policy and log.
final class DecisionBox: @unchecked Sendable {
  private let lock = NSLock()
  private var _policy: PermissionPolicy = { allow($0) }
  private var _entries: [(JSON, JSON)] = []
  var policy: PermissionPolicy {
    get { lock.withLock { _policy } }
    set { lock.withLock { _policy = newValue } }
  }
  func log(_ a: JSON, _ d: JSON) { lock.withLock { _entries.append((a, d)) } }
  var entries: [(JSON, JSON)] { lock.withLock { _entries } }
  var count: Int { entries.count }
}
