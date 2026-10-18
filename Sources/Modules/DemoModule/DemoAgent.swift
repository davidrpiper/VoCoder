// The demo's scripted agent turn and its fake repository: every prompt streams a reply, runs a
// shell command that needs approval, reads a file, updates its todos and ends with a summary, so
// `--demo` shows everything the repo tab draws.
import Foundation
import VoCoderCore
import VoCoderFakes

enum DemoAgent {
  static let files = [
    "README.md": "# vocoder-demo\n\nA pretend project for `vocoder --demo`.\n",
    "Sources/App.swift": "import Foundation\n\nprint(\"Hello\")\n",
    "Package.swift": "// swift-tools-version: 6.2\n",
  ]

  /// A repository with a commit, a modified file and an untracked one.
  static func makeRepository(in sourceControl: FakeSourceControl, at root: URL) {
    let repository = sourceControl.makeRepository(at: root, files: files)
    repository.write("Sources/App.swift", "import Foundation\n\nprint(\"Hello, demo\")\n")
    repository.write("notes.md", "Try the repo tab.\n")
  }

  static func behavior(pace: Duration) -> FakeAgentBackend.Behavior {
    { session, prompt in
      func pause() async { if pace > .zero { try? await Task.sleep(for: pace) } }
      func stream(_ text: String) async {
        let id = session.nextMessageID()
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
          session.emit(.textDelta(AgentTextDelta(messageID: id, text: word + " ")))
          await pause()
        }
        session.emit(.text(AgentText(messageID: id, text: text)))
      }

      session.beginTurn()
      session.emit(.status(.requesting))
      await pause()
      await stream("I'll check what changed in the work tree first.")
      session.emit(
        .todos([
          AgentTodo(id: "1", subject: "Look at the changes", status: .inProgress),
          AgentTodo(id: "2", subject: "Answer the question"),
        ]))
      let shell = AgentToolUse(
        id: "demo-tool-\(session.nextMessageID())", name: "Bash",
        input: .object([
          "command": .string("git status --short"),
          "description": .string("List changed files"),
        ]))
      session.emit(.toolUse(shell))
      let decision = await session.requestPermission(
        PermissionRequest(
          id: "demo-perm-\(shell.id)", toolName: "Bash", input: shell.input,
          description: "List changed files", toolUseID: shell.id, offersSessionRule: true))
      if case .deny(let message) = decision {
        session.emit(
          .toolResult(
            AgentToolResult(toolUseID: shell.id, toolName: "Bash", content: message, isError: true))
        )
      } else {
        session.emit(
          .toolResult(
            AgentToolResult(
              toolUseID: shell.id, toolName: "Bash", content: " M Sources/App.swift\n?? notes.md")))
      }
      await pause()
      let read = AgentToolUse(
        id: "demo-tool-\(session.nextMessageID())", name: "Read",
        input: .object(["file_path": .string("/demo/vocoder-demo/Sources/App.swift")]))
      session.emit(.toolUse(read))
      session.emit(
        .toolResult(
          AgentToolResult(
            toolUseID: read.id, toolName: "Read",
            content: "1\timport Foundation\n2\t\n3\tprint(\"Hello, demo\")")))
      session.emit(
        .todos([
          AgentTodo(id: "1", subject: "Look at the changes", status: .completed),
          AgentTodo(id: "2", subject: "Answer the question", status: .inProgress),
        ]))
      await pause()
      await stream(
        "## What I found\n\nYou asked: **\(prompt)**\n\n- `Sources/App.swift` now greets the demo\n"
          + "- `notes.md` is new and untracked\n\nNothing else changed.")
      session.emit(.spokenSummary("Two files changed: App.swift and a new notes file."))
      session.emit(
        .todos([
          AgentTodo(id: "1", subject: "Look at the changes", status: .completed),
          AgentTodo(id: "2", subject: "Answer the question", status: .completed),
        ]))
      session.endTurn(.completed)
    }
  }
}
