import Foundation
import Testing

@testable import VoCoderCore

@Suite struct LoggingTests {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: "vocoder-log-tests-\(UUID().uuidString)", directoryHint: .isDirectory)

  func contents(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

  @Test func writesFormattedLines() throws {
    let sink = FileLogSink(directory: directory)
    Log(category: "test", sink: sink).info("hello")
    let text = try contents(sink.currentFile)
    #expect(text.hasSuffix(" INFO [test] hello\n"))
  }

  @Test func dropsEntriesBelowMinimumLevel() throws {
    let sink = FileLogSink(directory: directory, minimumLevel: .notice)
    let log = Log(category: "test", sink: sink)
    log.debug("debug")
    log.info("info")
    log.error("error")
    let text = try contents(sink.currentFile)
    #expect(!text.contains("debug") && !text.contains("info"))
    #expect(text.contains("ERROR [test] error"))
  }

  @Test func rotatesBySizeKeepingMaxFiles() throws {
    let sink = FileLogSink(directory: directory, maxBytes: 200, maxFiles: 3)
    let log = Log(category: "rot", sink: sink)
    for index in 0..<30 { log.info("entry \(index) " + String(repeating: "x", count: 40)) }

    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    #expect(files == ["vocoder.1.log", "vocoder.2.log", "vocoder.log"])
    for index in 0..<3 {
      let size = try contents(sink.file(index: index)).utf8.count
      #expect(size <= 200)
    }
    #expect(try contents(sink.currentFile).contains("entry 29 "))
    #expect(try !contents(sink.file(index: 2)).contains("entry 0 "))
  }

  @Test func appendsToExistingFile() throws {
    Log(category: "a", sink: FileLogSink(directory: directory)).info("first")
    Log(category: "b", sink: FileLogSink(directory: directory)).info("second")
    let lines = try contents(FileLogSink(directory: directory).currentFile)
      .split(separator: "\n")
    #expect(lines.count == 2)
  }

  @Test func concurrentWritesAreNotInterleaved() async throws {
    let sink = FileLogSink(directory: directory)
    let log = Log(category: "c", sink: sink)
    await withTaskGroup { group in
      for index in 0..<200 { group.addTask { log.info("line \(index)") } }
    }
    let lines = try contents(sink.currentFile).split(separator: "\n")
    #expect(lines.count == 200)
    #expect(lines.allSatisfy { $0.contains(" INFO [c] line ") })
  }
}

@Suite struct BuildInfoTests {
  @Test func displayString() {
    #expect(BuildInfo(version: "0.1.0", build: "7").displayString == "0.1.0 (7)")
  }
}
