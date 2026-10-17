import Darwin
import Foundation

// Option A: `--permission-prompt-tool mcp__vocoder__approve`. Claude Code spawns
// `cc-spike mcp-permission --socket <path>` as a stdio MCP server; each `tools/call` is forwarded
// over a Unix socket to the driver, which decides, and the answer goes back as tool output.

/// Hand-rolled MCP stdio server (newline-delimited JSON-RPC 2.0). Runs until stdin closes.
func runMCPPermissionServer(socketPath: String) {
  func reply(_ id: JSON, result: JSON) {
    print(JSON.object(["jsonrpc": "2.0", "id": id, "result": result]).line)
    fflush(stdout)
  }
  func replyError(_ id: JSON, _ code: Int, _ message: String) {
    print(JSON.object(["jsonrpc": "2.0", "id": id, "error": ["code": .int(code), "message": .string(message)]]).line)
    fflush(stdout)
  }

  while let line = readLine() {
    guard let msg = try? JSON.parse(line) else { continue }
    let method = msg["method"]?.string ?? ""
    guard let id = msg["id"] else { continue }  // notifications (e.g. notifications/initialized)
    switch method {
    case "initialize":
      reply(
        id,
        result: [
          "protocolVersion": msg["params"]?["protocolVersion"] ?? "2025-06-18",
          "capabilities": ["tools": [:]],
          "serverInfo": ["name": "vocoder", "version": "0.0.1"],
        ])
    case "ping":
      reply(id, result: [:])
    case "tools/list":
      reply(
        id,
        result: [
          "tools": [
            [
              "name": "approve",
              "description": "VoCoder permission prompt",
              "inputSchema": [
                "type": "object",
                "properties": [
                  "tool_name": ["type": "string"], "input": ["type": "object"],
                  "tool_use_id": ["type": "string"],
                ],
                "required": ["tool_name", "input"],
              ],
            ]
          ]
        ])
    case "tools/call":
      let args = msg["params"]?["arguments"] ?? [:]
      let decision = UnixSocket.request(path: socketPath, args) ?? ["behavior": "deny", "message": "VoCoder unreachable"]
      reply(id, result: ["content": [["type": "text", "text": .string(decision.line)]]])
    default:
      replyError(id, -32601, "method not found: \(method)")
    }
  }
}

/// Line-delimited JSON over a Unix domain socket: one request line, one response line per
/// connection.
enum UnixSocket {
  private static func address(_ path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
      let bytes = Array(path.utf8.prefix(buf.count - 1))
      buf.copyBytes(from: bytes)
      buf[bytes.count] = 0
    }
    return addr
  }

  private static func readLine(_ fd: Int32) -> String? {
    var data = Data()
    var byte: UInt8 = 0
    while read(fd, &byte, 1) == 1 {
      if byte == UInt8(ascii: "\n") { return String(decoding: data, as: UTF8.self) }
      data.append(byte)
    }
    return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
  }

  private static func writeLine(_ fd: Int32, _ s: String) {
    let bytes = Array((s + "\n").utf8)
    _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
  }

  static func request(path: String, _ msg: JSON) -> JSON? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var addr = address(path)
    let ok = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard ok == 0 else { return nil }
    writeLine(fd, msg.line)
    return readLine(fd).flatMap { try? JSON.parse($0) }
  }

  /// Listens on `path`; each connection's request is answered by `handler` (async).
  static func serve(path: String, handler: @escaping @Sendable (JSON) async -> JSON) throws {
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = address(path)
    let ok = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard ok == 0, listen(fd, 8) == 0 else { throw POSIXError(.EADDRINUSE) }
    let thread = Thread {
      while true {
        let conn = accept(fd, nil, nil)
        if conn < 0 { return }
        guard let line = readLine(conn), let req = try? JSON.parse(line) else {
          close(conn)
          continue
        }
        Task {
          let resp = await handler(req)
          writeLine(conn, resp.line)
          close(conn)
        }
      }
    }
    thread.start()
  }
}
