import Foundation
import Testing
import VoCoderUIBridge

@testable import VoCoderUI

@MainActor
@Suite struct ScreenDumpTests {
  private func temporaryPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("screen-dump-\(UUID().uuidString).json").path
  }

  private func read(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  @Test func writesTheScreenOnlyWhenItChanges() throws {
    let path = temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let model = Counter()
    let host = UIHost(theme: .dark) { Text("count \(model.value)").foreground(.accent) }
    host.render()
    let dump = ScreenDump(host: host, path: path) { (width: 20, height: 2) }

    dump.dumpIfChanged()
    var object = try read(path)
    #expect(object["seq"] as? Int == 1)
    #expect(object["width"] as? Int == 20)
    #expect(object["height"] as? Int == 2)
    #expect(object["text"] as? String == lines("count 0", ""))
    let ansi = try #require(object["ansi"] as? String)
    #expect(ansi.contains("count 0") && ansi.contains("\u{1B}["))

    dump.dumpIfChanged()
    #expect(try read(path)["seq"] as? Int == 1)  // unchanged: not rewritten

    model.value = 1
    host.render()
    dump.dumpIfChanged()
    object = try read(path)
    #expect(object["seq"] as? Int == 2)
    #expect(object["text"] as? String == lines("count 1", ""))
  }

  @Test func nothingBeforeTheFirstFrame() {
    let path = temporaryPath()
    let host = UIHost(theme: .dark) { Text("hi") }
    ScreenDump(host: host, path: path) { (width: 0, height: 0) }.dumpIfChanged()
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  @Test func onlyWhenTheEnvironmentAsks() {
    let host = UIHost(theme: .dark) { Text("hi") }
    #expect(ScreenDump.fromEnvironment(host: host, environment: [:]) == nil)
    #expect(ScreenDump.fromEnvironment(host: host, environment: ["VOCODER_DUMP_SCREEN": ""]) == nil)
    #expect(
      ScreenDump.fromEnvironment(host: host, environment: ["VOCODER_DUMP_SCREEN": "/tmp/x"]) != nil)
  }
}

@MainActor
@Observable
private final class Counter {
  var value = 0
}
