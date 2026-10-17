import Foundation
import Testing

@testable import VoCoderUITestSupport

@Suite struct SnapshotHelperTests {
  @Test func goldenPathIsNextToTheTestFile() {
    let url = snapshotURL(
      filePath: "/repo/Tests/VoCoderUITests/ListTests.swift", function: "selected(row:)",
      name: "dark", ext: "ansi")
    #expect(url.path == "/repo/Tests/VoCoderUITests/__Snapshots__/ListTests/selected.dark.ansi")
  }

  @Test func diffMarksChangedLines() {
    #expect(lineDiff("a\nb\nc", "a\nB\nc\nd") == "  a\n- b\n+ B\n  c\n+ d")
    #expect(lineDiff("\u{1B}[1mx\r\n", "x\r\n").contains("- \\u{1B}[1mx\\r"))
  }
}
