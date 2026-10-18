// How the repo tab looks: the conversation with the approval card and the prompt below it, and
// a side panel (branch, changed files, todos) on the right.
import Foundation
import VoCoderCore
import VoCoderUI

extension RepoTab {
  static let panelWidth = 30
  /// Result lines shown when a tool call is expanded.
  static let resultLines = 12

  var body: some View {
    HStack {
      VStack {
        conversationBox.flex()
        if let request = conversation.pendingApproval {
          ApprovalCard(tab: self, request: request, queued: conversation.approvals.count - 1)
        }
        promptBox
      }
      .flex()
      if showsPanel {
        SidePanel(tab: self).frame(width: .exactly(Self.panelWidth))
      }
    }
  }

  private var conversationBox: some View {
    ContextReader { context in
      ScrollView(self.conversationID, state: self.scroll, onAction: self.conversationAction) {
        ConversationView(tab: self)
      }
      .border(
        .rounded, title: self.agentTitle,
        color: context.isFocused(self.conversationID) ? .focus : .border)
    }
  }

  private var promptBox: some View {
    ContextReader { context in
      TextField(
        self.promptID, placeholder: "Prompt (Enter sends, Alt-Enter adds a line)",
        submitsOnEnter: true, onAction: self.promptAction, onChange: self.promptChanged,
        onSubmit: self.send
      )
      .frame(height: .atMost(6))
      .border(
        .rounded, title: "Prompt",
        color: context.isFocused(self.promptID) ? .focus : .border)
    }
  }

  /// "Claude Code · working", "Claude Code · not started".
  var agentTitle: String {
    let name = agent?.displayName ?? "No agent"
    let state: String
    switch phase {
    case .notStarted: state = "starts with your first prompt"
    case .starting: state = "starting…"
    case .failed: state = "not running"
    case .running:
      if conversation.pendingApproval != nil {
        state = "needs approval"
      } else if conversation.isWorking {
        state = "working…"
      } else {
        state = conversation.session?.model.map { "ready · \($0)" } ?? "ready"
      }
    }
    return "\(name) · \(state)"
  }
}

/// The transcript.
struct ConversationView: View {
  let tab: RepoTab

  var body: some View {
    let conversation = tab.conversation
    if conversation.entries.isEmpty {
      Paragraph(emptyText).foreground(.muted)
    }
    for entry in conversation.entries {
      EntryView(tab: tab, entry: entry)
    }
    if conversation.isWorking && conversation.pendingApproval == nil {
      Text("◐ working…").foreground(.muted)
    }
  }

  private var emptyText: String {
    if case .failed(let reason) = tab.phase { return reason }
    guard let agent = tab.agent else {
      return "No coding agent is enabled: enable the claude-code module in the config."
    }
    return "Ask \(agent.displayName) something about \(tab.root.name): type below and press"
      + " Enter."
  }
}

struct EntryView: View {
  let tab: RepoTab
  let entry: Conversation.Entry

  var body: some View {
    switch entry {
    case .prompt(_, let text):
      VStack {
        Text("")
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
          .enumerated()
        {
          HStack {
            Text(index == 0 ? "› " : "  ").foreground(.accent).bold()
            Paragraph(String(line)).bold().flex(.horizontal)
          }
        }
      }
    case .message(let message):
      if message.isNested {
        HStack {
          Text("  │ ").foreground(.muted)
          Markdown(document: message.document).flex(.horizontal)
        }
      } else {
        Markdown(document: message.document)
      }
    case .tool(let tool):
      ToolCallView(
        tool: tool, roots: tab.rootPaths, isSelected: tab.selectedTool == tool.id,
        isExpanded: tab.expandedTools.contains(tool.id))
    case .notice(_, let notice):
      Paragraph(notice.text).foreground(notice.kind == .error ? .danger : .muted)
    case .turnEnd(_, let end):
      Text(TurnFooter.text(end)).foreground(TurnFooter.color(end))
    }
  }
}

/// `▸ Bash  git status  ✓`, with input and result when expanded.
struct ToolCallView: View {
  let tool: Conversation.ToolCall
  let roots: [String]
  let isSelected: Bool
  let isExpanded: Bool

  var body: some View {
    let indent = tool.use.parentToolUseID == nil ? "" : "  │ "
    VStack {
      HStack {
        Text(indent).foreground(.muted)
        Text(isExpanded ? "▾ " : "▸ ").foreground(.muted)
        Text(tool.use.name).foreground(.info).bold()
        Text("  ")
        Text(ToolSummary.summary(name: tool.use.name, input: tool.use.input, roots: roots))
          .foreground(.muted).flex(.horizontal)
        Text(" " + mark).foreground(markColor)
      }
      .background(isSelected ? .selection : nil)
      .foreground(isSelected ? .selectionText : nil)
      .keepVisible(isSelected)
      if isExpanded {
        // A gutter, not a box: a box's border merges with the conversation's when scrolled.
        let gutter = indent + "  ┊ "
        for line in ToolSummary.detail(of: tool.use.input).split(
          separator: "\n", omittingEmptySubsequences: false)
        {
          HStack {
            Text(gutter).foreground(.muted)
            Paragraph(String(line)).foreground(.accent).flex(.horizontal)
          }
        }
        if let result = tool.result {
          let shown = ToolSummary.truncated(result.content, maxLines: RepoTab.resultLines)
          for line in shown.lines {
            HStack {
              Text(gutter).foreground(.muted)
              Text(line).foreground(result.isError ? .danger : nil)
            }
          }
          if shown.omitted > 0 {
            HStack {
              Text(gutter).foreground(.muted)
              Text("… \(shown.omitted) more line\(shown.omitted == 1 ? "" : "s")")
                .foreground(.muted)
            }
          }
        }
      }
    }
  }

  private var mark: String {
    if tool.awaitingApproval { return "● approval" }
    if tool.denied { return "✗ denied" }
    guard let result = tool.result else { return "…" }
    return result.isError ? "✗" : "✓"
  }

  private var markColor: Color {
    if tool.awaitingApproval { return .warning }
    if tool.denied || tool.result?.isError == true { return .danger }
    return tool.result == nil ? .muted : .success
  }
}

enum TurnFooter {
  /// "── done · 12.3 s · $0.04 ──", "── interrupted ──".
  static func text(_ end: AgentTurnEnd) -> String {
    var parts: [String]
    switch end.outcome {
    case .completed: parts = ["done"]
    case .interrupted: parts = ["interrupted"]
    case .failed(let message): parts = ["failed: \(message)"]
    }
    if let duration = end.duration {
      let seconds =
        Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1e18
      parts.append(String(format: "%.1f s", seconds))
    }
    if let cost = end.costUSD { parts.append(String(format: "$%.2f", cost)) }
    return "── " + parts.joined(separator: " · ") + " ──"
  }

  static func color(_ end: AgentTurnEnd) -> Color {
    if case .failed = end.outcome { return .danger }
    return .muted
  }
}

/// The oldest waiting permission request with its answers.
struct ApprovalCard: View {
  let tab: RepoTab
  let request: PermissionRequest
  let queued: Int

  var body: some View {
    ContextReader { context in
      VStack {
        if let description = request.description, !description.isEmpty {
          Paragraph(description)
        }
        Paragraph(ToolSummary.detail(of: request.input)).foreground(.accent)
        if let path = request.blockedPath {
          Paragraph("Outside the allowed paths: \(path)").foreground(.warning)
        }
        HStack {
          Button(tab.approvalID.appending("once"), "a Allow") {
            Task { await tab.respond(.allowOnce) }
          }
          if request.offersSessionRule {
            Text(" ")
            Button(tab.approvalID.appending("session"), "s Allow for session") {
              Task { await tab.respond(.allowForSession) }
            }
          }
          Text(" ")
          Button(tab.approvalID.appending("deny"), "d Deny") {
            Task { await tab.respond(.deny(message: RepoCommands.denyMessage)) }
          }
          Spacer()
        }
      }
      .border(
        .rounded, title: title,
        color: context.containsFocus(tab.approvalID) ? .warning : .border)
    }
    .focusScope(tab.approvalID) { [tab] action in
      guard action == .cancel else { return false }
      tab.focusPrompt()
      return true
    }
  }

  private var title: String {
    "Allow \(request.displayName)?" + (queued > 0 ? " (+\(queued) waiting)" : "")
  }
}

/// Branch, changed files and the agent's todos.
struct SidePanel: View {
  let tab: RepoTab

  var body: some View {
    VStack {
      VStack {
        if let status = tab.status {
          Text(branchLine(status)).bold()
          if status.isClean {
            Text("clean").foreground(.muted)
          }
        } else if let error = tab.gitError {
          Paragraph(error).foreground(.danger)
        } else {
          Text("…").foreground(.muted)
        }
      }
      .border(.rounded, title: "Git", color: .border)
      if let status = tab.status, !status.isClean {
        ContextReader { context in
          ListView(tab.filesID, state: tab.files, items: status.files) { file, _ in
            HStack {
              Text(Self.marker(file) + " ").foreground(Self.color(file))
              Text(file.path)
              Spacer()
            }
          }
          .border(
            .rounded, title: "Changes (\(status.files.count))",
            color: context.containsFocus(tab.filesID) ? .focus : .border)
        }
        .flex()
      }
      VStack {
        if tab.conversation.todos.isEmpty {
          Text("No todos").foreground(.muted)
        }
        for todo in tab.conversation.todos {
          HStack {
            Text(Self.marker(todo) + " ").foreground(Self.color(todo))
            Paragraph(todo.subject).foreground(todo.status == .completed ? .muted : nil)
              .flex(.horizontal)
          }
        }
      }
      .border(.rounded, title: "Todos", color: .border)
      Spacer()
    }
  }

  private func branchLine(_ status: RepoStatus) -> String {
    var line = status.branch ?? status.head.map { "detached \($0.short)" } ?? "no commits"
    if status.ahead > 0 { line += " ↑\(status.ahead)" }
    if status.behind > 0 { line += " ↓\(status.behind)" }
    return line
  }

  /// Git's short status letters: `M`, `A`, `D`, `R`, `?`, `U`.
  static func marker(_ file: ChangedFile) -> String {
    if file.isConflicted { return "U" }
    if file.isUntracked { return "?" }
    switch file.staged ?? file.unstaged {
    case .added: return "A"
    case .deleted: return "D"
    case .renamed: return "R"
    case .copied: return "C"
    case .typeChanged: return "T"
    case .modified, nil: return "M"
    }
  }

  static func color(_ file: ChangedFile) -> Color {
    if file.isConflicted { return .danger }
    if file.isUntracked { return .muted }
    return file.staged != nil ? .success : .warning
  }

  static func marker(_ todo: AgentTodo) -> String {
    switch todo.status {
    case .pending: "○"
    case .inProgress: "◐"
    case .completed: "✓"
    }
  }

  static func color(_ todo: AgentTodo) -> Color {
    switch todo.status {
    case .pending: .muted
    case .inProgress: .accent
    case .completed: .success
    }
  }
}
