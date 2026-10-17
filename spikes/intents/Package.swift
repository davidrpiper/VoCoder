// swift-tools-version: 6.2
// P0-05 spike: on-device Foundation Models for intent parsing (guided generation) and for
// summarising agent turns into speakable text. Measures accuracy and latency.
import PackageDescription

let package = Package(
  name: "intents-spike",
  platforms: [.macOS("26.4")],
  targets: [
    .executableTarget(
      name: "intent-spike",
      path: "Sources/intent-spike"
    )
  ]
)
