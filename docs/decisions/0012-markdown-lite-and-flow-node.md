# 0012 — Markdown-lite: document model in Core, renderer in UI, bridge `flow` node

- Status: Accepted
- Date: 2026-10-18
- WP: P1-03b

## Context

Agent output (P1-10) and Notion pages (P5-02) are markdown. They need to be readable in the
terminal: headings, code, lists, quotes, and inline emphasis that still wraps. The bridge's
`paragraph` wraps only plain text: FTXUI's `paragraph` is a flexbox of single-style words. PLAN
put the whole renderer in `VoCoderUI`. Voice will also need markdown later: read-aloud (P5-02)
and spoken summaries (P2-06) want the text without the markup. `VoCoderVoice` doesn't import
`VoCoderUI`, though. ADR 0004 rules out third-party markdown libraries.

## Decision

- **The document model and parser live in Core** (`VoCoderCore/Text/`). `MarkdownDocument`
  holds `MarkdownBlock`s (heading, paragraph, fenced code with its info string, list, quote,
  rule, pipe table) and `MarkdownInline`s (text, strong, emphasis, strikethrough, code, link,
  soft/hard break), plus `plainText`. The parser is hand-written and CommonMark-like, with two
  passes: blocks line by line (container blocks strip their markers and recurse), then inlines
  over characters. It **never fails**: anything unrecognised or malformed stays text.
  - An unclosed fence runs to the end of the document.
  - An unclosed `**`/`` ` ``/`[` stays literal (`**a*` is `*` + emphasis, as in CommonMark).
  - Lenient where agents are sloppy: two spaces of indentation are enough to nest under `1. `.
  - Only bullets and `1.` interrupt a paragraph.
  - Pipe tables, when the next line is a delimiter row, are kept as source lines.
  - Out of scope: indented code, reference links, HTML, laid-out tables.
  - Bounded: quotes, list items, emphasis and links nest at most 32 deep (deeper markers are
    text). Searches for a closer look at most 4096 characters ahead, so pathological input
    stays linear-ish.
- **Rendering lives in `VoCoderUI`**: `Markdown(_ source:)`, or `Markdown(document:)` so callers
  can parse once and render many times (streamed agent messages).
  - H1 bold in the accent colour, H2 bold, H3 and below bold in the muted colour.
  - Code blocks have the `codeBackground` role across the full width and never wrap.
  - Bullets change by level (`•` `◦` `▪`). Numbers keep the source numbers and are
    right-aligned, and wrapped lines hang under the text.
  - Quotes have a `│` bar in the border colour. Rules are a divider.
  - Links show their text, underlined in the accent colour.
  - One blank line between blocks, none inside list items.
- **New bridge node `flow`** (`+[VCNode flow:]`, `Flow.mm`) with a public `Flow` view. Its
  children are words, one space apart, wrapped at the available width (an FTXUI flexbox like
  `paragraph`). It flexes horizontally, so in an `hbox` after a marker it takes the rest of
  the row.
  - Swift sends one child per word. A word that mixes styles (`**bold**,`) is an `hbox` of
    styled `text`s, so punctuation stays attached.
  - Inline code is kept as one word, so `git status` never wraps in the middle.
  - **Over-wide words break instead of being clipped.** Each child is wrapped in a
    `BreakableWord` node. When its box is narrower than the word (FTXUI would clip it), it
    draws the word in line-wide slices on consecutive rows. Like FTXUI's flexbox, it learns its
    width from the previous layout pass and asks for another pass (`Check`) when the width
    changes. Long paths and URLs in agent output stay readable.

## Consequences

- P1-10 renders agent messages with `Markdown(document:)` and caches the parsed document per
  message (re-parse only the message that is still streaming).
- Voice (P2-06, P5-02) can read `MarkdownDocument.plainText`, or walk the blocks for richer
  speech ("code block omitted"), without UI.
- Underline and strikethrough stop at the gaps between words: the gaps belong to the flow, not
  to the styled words. That's acceptable for links. If it ever matters, the flow could carry
  per-gap styles.
- Terminal.app doesn't draw strikethrough (SGR 9); Ghostty does.
- Tables are shown as their source lines, unwrapped. Real table layout (the bridge already has
  `table`) can come later without changing the model much: add cells to `.table`.
- `make term-test` checks the gallery's Markdown page (page 6) in Terminal.app: the window text
  matches the off-screen render, and the code background is checked against a screenshot.

## Alternatives considered

- **Everything in `VoCoderUI`** (as PLAN said): voice would need its own parser or a UI
  dependency.
- **Wrapping styled text in Swift** (measuring words, emitting lines): the width is only known
  during FTXUI layout, and wide characters need FTXUI's width tables. That means rebuilding on
  every resize, and it duplicates FTXUI.
- **Code spans split into words like other text**: a command would wrap mid-way, and the
  background would have uncoloured gaps.
- **A third-party parser (swift-markdown/cmark)**: ruled out by ADR 0004. It would also be far
  more than the subset needs.
