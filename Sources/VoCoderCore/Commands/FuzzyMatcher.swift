// Fuzzy matching for the palette (own implementation, ADR 0004). The query's characters must
// appear in order, ignoring case; matches at word starts and runs of consecutive characters
// score higher, gaps cost a little.

public enum FuzzyMatcher {
  /// Score of `query` against `candidate`, nil when it doesn't match. Higher is better; an
  /// empty query matches everything with 0.
  public static func score(_ query: String, in candidate: String) -> Int? {
    let needle = Array(query.lowercased().filter { !$0.isWhitespace })
    guard !needle.isEmpty else { return 0 }
    let original = Array(candidate)
    let haystack = original.map { Character($0.lowercased()) }
    guard needle.count <= haystack.count else { return nil }

    let starts = original.indices.map { isWordStart(original, $0) }
    // previous[j]: best score with the needle so far matched and its last character at
    // haystack[j - 1]; nil where that's impossible.
    var previous = [Int?](repeating: nil, count: haystack.count + 1)
    for i in 1...needle.count {
      var current = [Int?](repeating: nil, count: haystack.count + 1)
      // Best previous-row score ending two or more positions back, minus the gap since.
      var gapped: Int?
      for j in i...haystack.count {
        if i > 1, j >= 2 {
          let decayed = gapped.map { $0 - 1 }
          let fresh = previous[j - 2].map { $0 - 1 }
          gapped = [decayed, fresh].compactMap { $0 }.max()
        }
        guard haystack[j - 1] == needle[i - 1] else { continue }
        var gain = 1 + (starts[j - 1] ? 8 : 0)
        if j == 1 { gain += 4 }
        if i == 1 {
          current[j] = gain - min(j - 1, 3)  // leading gap, capped
        } else {
          let consecutive = previous[j - 1].map { $0 + gain + 5 }
          let afterGap = gapped.map { $0 + gain }
          current[j] = [consecutive, afterGap].compactMap { $0 }.max()
        }
      }
      previous = current
    }
    return previous.compactMap { $0 }.max()
  }

  private static func isWordStart(_ characters: [Character], _ index: Int) -> Bool {
    guard index > 0 else { return true }
    let before = characters[index - 1]
    let here = characters[index]
    if !(before.isLetter || before.isNumber) { return here.isLetter || here.isNumber }
    return before.isLowercase && here.isUppercase  // camelCase
  }
}

/// Ranks commands for the palette.
public enum CommandSearch {
  /// Commands matching `query`, best first. Title matches count fully; ids, voice phrases and
  /// categories a bit less. Ties go to recently used commands, then registration order. An
  /// empty query lists recent commands first, then the rest in registration order.
  public static func rank(_ query: String, _ commands: [Command], recent: [CommandID] = [])
    -> [Command]
  {
    let recency = Dictionary(
      recent.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    let scored: [(command: Command, score: Int, order: Int)] = commands.enumerated()
      .compactMap { order, command in
        guard let score = score(query, command) else { return nil }
        return (command, score, order)
      }
    return scored.sorted { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score > rhs.score }
      let lr = recency[lhs.command.id] ?? Int.max
      let rr = recency[rhs.command.id] ?? Int.max
      if lr != rr { return lr < rr }
      return lhs.order < rhs.order
    }.map(\.command)
  }

  static func score(_ query: String, _ command: Command) -> Int? {
    let fields: [(String, Int)] =
      [(command.title, 4), (command.id.rawValue, 3), (command.category, 2)]
      + command.voicePhrases.map { ($0, 3) }
    // Weighted by quarters so a title match beats the same match in an id.
    let scores = fields.compactMap { text, weight in
      FuzzyMatcher.score(query, in: text).map { $0 * weight }
    }
    return scores.max()
  }
}
