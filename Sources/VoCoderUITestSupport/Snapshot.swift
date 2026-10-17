// Golden-file snapshot tests for views (ADR 0004: own helper over the bridge's off-screen
// render). Goldens live next to the test file in `__Snapshots__/<TestFile>/<test>.<ext>`;
// `make snapshot-update` (VOCODER_SNAPSHOT_UPDATE=1) rewrites them — review the diff.
import Foundation
import Testing
import VoCoderUI
import VoCoderUIBridge

public enum SnapshotFormat: Sendable, Equatable {
  /// Characters only, trailing spaces trimmed.
  case plain
  /// With ANSI colours and styles, degraded to `depth` (view with `cat`).
  case ansi(VCColorDepth = .trueColor)

  var fileExtension: String {
    switch self {
    case .plain: "txt"
    case .ansi(.trueColor): "ansi"
    case .ansi(.palette256): "ansi256"
    case .ansi(.palette16): "ansi16"
    case .ansi: "ansi1"
    }
  }
}

/// Renders `view` at `width`×`height` (`height` 0 fits the content) and compares it with its
/// golden. `focus` is focused before rendering.
@MainActor
public func assertSnapshot(
  of view: some View, width: Int, height: Int = 0, theme: Theme = .dark,
  focus: FocusID? = nil, format: SnapshotFormat = .plain, named name: String? = nil,
  filePath: String = #filePath, function: String = #function,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let host = UIHost(theme: theme) { view }
  if let focus { host.focus.focus(focus) }
  host.render()
  assertSnapshot(
    of: host, width: width, height: height, format: format, named: name, filePath: filePath,
    function: function, sourceLocation: sourceLocation)
}

/// Snapshot of a host's current state (after keys, focus moves, model changes).
@MainActor
public func assertSnapshot(
  of host: UIHost, width: Int, height: Int = 0, format: SnapshotFormat = .plain,
  named name: String? = nil, filePath: String = #filePath, function: String = #function,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  host.renderIfNeeded()
  let actual =
    switch format {
    case .plain: host.renderer.renderToString(width: width, height: height, ansi: false)
    case .ansi(let depth):
      host.renderer.renderToString(width: width, height: height, colorDepth: depth)
    }
  assertSnapshot(
    actual, fileExtension: format.fileExtension, named: name, filePath: filePath,
    function: function, sourceLocation: sourceLocation)
}

/// Compares `actual` with the golden for the calling test, recording it if missing.
public func assertSnapshot(
  _ actual: String, fileExtension: String = "txt", named name: String? = nil,
  filePath: String = #filePath, function: String = #function,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  let url = snapshotURL(filePath: filePath, function: function, name: name, ext: fileExtension)
  let update = ProcessInfo.processInfo.environment["VOCODER_SNAPSHOT_UPDATE"] == "1"
  let expected = try? String(contentsOf: url, encoding: .utf8)
  if expected == actual { return }
  if update || expected == nil {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try actual.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      Issue.record("Could not write snapshot \(url.path): \(error)", sourceLocation: sourceLocation)
      return
    }
    if !update {
      Issue.record(
        "Recorded new snapshot \(url.lastPathComponent); review it and run again.\n\(actual)",
        sourceLocation: sourceLocation)
    }
    return
  }
  let message =
    "Snapshot \(url.lastPathComponent) differs (- golden, + actual; `make snapshot-update` to "
    + "accept):\n\(lineDiff(expected ?? "", actual))"
  Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
}

func snapshotURL(filePath: String, function: String, name: String?, ext: String) -> URL {
  let file = URL(fileURLWithPath: filePath)
  let test = String(function.prefix { $0 != "(" })
  return file.deletingLastPathComponent()
    .appendingPathComponent("__Snapshots__")
    .appendingPathComponent(file.deletingPathExtension().lastPathComponent)
    .appendingPathComponent(test + (name.map { "." + $0 } ?? "") + "." + ext)
}

/// Line-by-line comparison; unchanged lines are shown with two spaces for context.
func lineDiff(_ expected: String, _ actual: String) -> String {
  // Split on scalars: "\r\n" is one Character, and ANSI snapshots use it.
  func split(_ s: String) -> [String] {
    s.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map {
      String(String.UnicodeScalarView($0)).debugDescription.dropFirst().dropLast().description
    }
  }
  let old = split(expected)
  let new = split(actual)
  var out: [String] = []
  for index in 0..<max(old.count, new.count) {
    let a = index < old.count ? old[index] : nil
    let b = index < new.count ? new[index] : nil
    if a == b {
      out.append("  " + (a ?? ""))
    } else {
      if let a { out.append("- " + a) }
      if let b { out.append("+ " + b) }
    }
  }
  return out.joined(separator: "\n")
}
