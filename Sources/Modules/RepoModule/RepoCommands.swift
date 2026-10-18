// The repo tab's commands (DESIGN §3.2): prompt, interrupt, approvals, tool calls, panel. They
// act on the selected repo tab and are unavailable elsewhere.
import Foundation
import VoCoderCore

public enum RepoCommands {
  public static let focusPrompt: CommandID = "agent.prompt"
  public static let send: CommandID = "agent.send"
  public static let interrupt: CommandID = "agent.interrupt"
  public static let approve: CommandID = "agent.approve"
  public static let approveForSession: CommandID = "agent.approveForSession"
  public static let deny: CommandID = "agent.deny"
  public static let denyWithReason: CommandID = "agent.denyWithReason"
  public static let nextTool: CommandID = "agent.nextTool"
  public static let previousTool: CommandID = "agent.previousTool"
  public static let restart: CommandID = "agent.restart"
  public static let newSession: CommandID = "agent.newSession"
  public static let togglePanel: CommandID = "repo.togglePanel"

  /// What the agent is told when the user denies without a reason.
  static let denyMessage = "The user denied this. Don't try it again unless asked."

  @MainActor
  static var all: [Command] {
    let onRepoTab: Command.Availability = { tab(in: $0) != nil }
    let hasApproval: Command.Availability = { tab(in: $0)?.conversation.pendingApproval != nil }
    let offersSession: Command.Availability = {
      tab(in: $0)?.conversation.pendingApproval?.offersSessionRule == true
    }
    let isWorking: Command.Availability = { tab(in: $0)?.conversation.isWorking == true }
    let inConversation: Command.Availability = { context in
      guard let tab = tab(in: context) else { return false }
      return context.focus.contains(tab.conversationID.rawValue)
    }
    return [
      Command(
        id: focusPrompt, title: "Write a prompt", category: "Agent", keys: ["<leader> i"],
        isAvailable: onRepoTab
      ) { context in
        tab(in: context)?.focusPrompt()
      },
      Command(
        id: send, title: "Send a prompt", category: "Agent",
        voicePhrases: ["tell claude", "ask claude"],
        params: [CommandParameter("prompt", title: "Prompt")], isAvailable: onRepoTab
      ) { context in
        guard let tab = tab(in: context), let prompt = context.arguments.text("prompt") else {
          return
        }
        tab.send(prompt)
      },
      Command(
        id: interrupt, title: "Interrupt the agent", category: "Agent", keys: ["<leader> x"],
        voicePhrases: ["interrupt", "stop the agent"], isAvailable: isWorking
      ) { context in
        await tab(in: context)?.interrupt()
        context.say("Interrupted")
      },
      Command(
        id: approve, title: "Approve", category: "Agent", keys: ["a", "<leader> a"],
        voicePhrases: ["approve", "allow it"], risk: .outward, confirmsInline: true,
        isAvailable: hasApproval
      ) { context in
        await tab(in: context)?.respond(.allowOnce)
        context.say("Approved")
      },
      Command(
        id: approveForSession, title: "Allow for this session", category: "Agent",
        keys: ["s", "<leader> s"], voicePhrases: ["always allow", "allow for this session"],
        risk: .outward, confirmsInline: true, isAvailable: offersSession
      ) { context in
        await tab(in: context)?.respond(.allowForSession)
        context.say("Allowed for this session")
      },
      Command(
        id: deny, title: "Deny", category: "Agent", keys: ["d", "<leader> D"],
        voicePhrases: ["deny", "don't allow"], isAvailable: hasApproval
      ) { context in
        await tab(in: context)?.respond(.deny(message: denyMessage))
        context.say("Denied")
      },
      Command(
        id: denyWithReason, title: "Deny with a reason", category: "Agent", keys: ["D"],
        isAvailable: hasApproval
      ) { context in
        guard let tab = tab(in: context) else { return }
        let request = TextRequest(title: "Why not?", placeholder: "Told to the agent")
        guard let reason = await context.prompter.askText(request) else { return }
        let message = reason.trimmingCharacters(in: .whitespaces)
        await tab.respond(.deny(message: message.isEmpty ? denyMessage : message))
        context.say("Denied")
      },
      Command(
        id: nextTool, title: "Next tool call", category: "Agent", keys: ["]"],
        isAvailable: inConversation
      ) { context in
        tab(in: context)?.selectTool(by: 1)
      },
      Command(
        id: previousTool, title: "Previous tool call", category: "Agent", keys: ["["],
        isAvailable: inConversation
      ) { context in
        tab(in: context)?.selectTool(by: -1)
      },
      Command(
        id: restart, title: "Restart the agent", category: "Agent", isAvailable: onRepoTab
      ) { context in
        await tab(in: context)?.restart(fresh: false)
      },
      Command(
        id: newSession, title: "New agent conversation", category: "Agent",
        voicePhrases: ["new conversation"], isAvailable: onRepoTab
      ) { context in
        guard let tab = tab(in: context) else { return }
        let request = ConfirmRequest(
          title: "Start a new conversation?",
          message: "The agent forgets this conversation; the transcript stays on screen.",
          confirmTitle: "New conversation")
        guard await context.prompter.confirm(request) else { return }
        await tab.restart(fresh: true)
      },
      Command(
        id: togglePanel, title: "Toggle side panel", category: "Repo", keys: ["<leader> r p"],
        isAvailable: onRepoTab
      ) { context in
        guard let tab = tab(in: context) else { return }
        tab.showsPanel.toggle()
      },
    ]
  }

  @MainActor
  static func tab(in context: CommandContext) -> RepoTab? {
    context.state.selectedTab as? RepoTab
  }
}
