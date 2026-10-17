/// What `vocoder config init` writes: every option, commented out where it has no safe default.
/// It must load without errors (tested).
public enum ConfigTemplate {
  public static let text = """
    # VoCoder configuration (DESIGN §4.9). Check it with `vocoder config check`;
    # `vocoder doctor` checks the rest of the setup. Secrets don't go here: use `vocoder auth <module>`.

    # One [[repo]] per repository; each gets a tab. Aliases name it by voice and in the palette.
    # [[repo]]
    # path = "~/projects/my-app"
    # aliases = ["my app", "the app"]

    [ui]
    theme = "auto"                    # auto (follows macOS) | dark | light

    [keys]
    leader = "ctrl+space"
    # Replace a command's default keys (ids are in the help overlay, `?`); [] unbinds.
    [keys.bindings]
    # "tab.next" = ["<leader> n", "alt+n"]

    [modules]
    # Compiled-in modules that shouldn't load: git, claude-code, calendar, linear, notion.
    disabled = []

    # Claude Code sessions: load your own MCP servers ("user") or none ("none"), and the
    # model (default: Claude Code's own).
    # [claude-code]
    # mcp_servers = "none"
    # model = "sonnet"

    """
}
