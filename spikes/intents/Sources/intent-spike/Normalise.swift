import Foundation

// Deterministic pre-processing the router would run before the grammar and model stages:
// spoken issue keys ("eng one forty two", "E N G dash one two three") → "ENG-142".

private let units = [
  "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
  "eight": 8, "nine": 9,
]
private let teens = [
  "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
  "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
]
private let tens = [
  "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80,
  "ninety": 90,
]

/// Reads digits spoken the way people say IDs: "one forty two" → "142", "one two three" → "123",
/// "ninety eight" → "98", "one hundred twenty three" → "123". Returns the digits and the number of
/// tokens consumed.
func spokenDigits(_ tokens: ArraySlice<String>) -> (String, Int)? {
  var groups: [Int] = []
  var i = tokens.startIndex
  while i < tokens.endIndex {
    let t = tokens[i]
    if let d = Int(t) { groups.append(d); i += 1; continue }
    if let u = units[t] { groups.append(u); i += 1; continue }
    if let v = teens[t] { groups.append(v); i += 1; continue }
    if let v = tens[t] {
      if i + 1 < tokens.endIndex, let u = units[tokens[i + 1]], u > 0 { groups.append(v + u); i += 2 }
      else { groups.append(v); i += 1 }
      continue
    }
    if t == "hundred", let last = groups.popLast() {
      var v = last * 100
      i += 1
      if i < tokens.endIndex, tokens[i] == "and" { i += 1 }
      if i < tokens.endIndex, let (rest, n) = spokenDigits(tokens[i..<min(i + 2, tokens.endIndex)]),
        let r = Int(rest), r < 100
      {
        v += r; i += n
      }
      groups.append(v)
      continue
    }
    break
  }
  guard !groups.isEmpty else { return nil }
  return (groups.map(String.init).joined(), i - tokens.startIndex)
}

func normaliseIssueKeys(_ text: String, prefixes: [String] = ["ENG"]) -> String {
  let raw = text.split(separator: " ").map(String.init)
  let lower = raw.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
  var out: [String] = []
  var i = 0
  outer: while i < raw.count {
    for p in prefixes {
      let letters = p.lowercased().map(String.init)
      var j = i
      // "eng" or "e n g"
      if lower[j] == p.lowercased() { j += 1 }
      else if j + letters.count <= lower.count, Array(lower[j..<j + letters.count]) == letters { j += letters.count }
      else { continue }
      if j < lower.count, lower[j] == "dash" || lower[j] == "-" { j += 1 }
      if let (digits, n) = spokenDigits(lower[j...]) {
        out.append("\(p)-\(digits)")
        i = j + n
        continue outer
      }
    }
    out.append(raw[i])
    i += 1
  }
  return out.joined(separator: " ")
}
