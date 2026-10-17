// swift-tools-version: 6.2
// P0-04 spike: drive `claude -p` in stream-json mode, answer permission prompts from our process
// (host control protocol and MCP permission tool), resume, interrupt, <spoken> compliance.
import PackageDescription

let package = Package(
  name: "claude-code-spike",
  platforms: [.macOS(.v26)],
  targets: [
    .executableTarget(name: "cc-spike", path: "Sources/cc-spike")
  ]
)
