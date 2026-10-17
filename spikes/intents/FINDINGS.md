# P0-05 — Foundation Models intent spike: findings

- Date: 2026-10-17 · macOS 26.6.2 · Xcode 27.1 / Swift 6.4 · on-device `SystemLanguageModel`
  (context 4096 tokens), greedy sampling throughout
- Run: `swift build -c release && .build/release/intent-spike <cmd>`:
  - `check`: model availability
  - `selftest`: scoring and normaliser checks, no model needed
  - `turns`: prints the summariser's inputs, no model needed
  - `intents --schema a|b|c --prompt plain|fewshot|context|tools|v2 [--normalise] [--prewarm] [--stream] [--permissive] [--repeat N] [--only 1,2]`
  - `summarise [--v2] [--permissive]`
  - `overflow`

  `run-all.sh` (round 1) and `run-round2.sh` reproduce the matrix. Per-run reports are in
  `results/*.md`, with per-utterance rows in `results/*.json`.
- **Utterance set:** `utterances.json`, kept for P2-05. 83 utterances, each labelled with
  acceptable kinds and expected slots. Ids 1–60 were used to tune the prompt. Ids 61–83 are a
  **hold-out set** written before tuning and never used for it. The app context (tabs, focused
  repo, pending permission, current issue, changed files) is in the same file.

## Verdict: **GO, as the middle routing stage only, with conservative handling of its output**

On-device intent parsing gets clean phrasings right (100%) and recognises vague ones (100%
`unclear`). On loosely phrased commands it gets **about 65–80% of intents right**, with ~70% on
the hold-out set. Prompt tuning did not move the hold-out number. Most misses come back as
`unclear`, which costs a clarifying question, not a wrong action. Wrong *actions* happen on
roughly 10% of utterances. One error was dangerous ("approve the PR once CI passes" → `approve`);
it is deterministic, and the risk-tier confirmation catches it.

Latency is **~1.15 s p50 without prewarm and ~0.8 s with prewarm**. The prewarm starts when
push-to-talk is pressed, so the <1 s target (DESIGN §8 #4) is met only with prewarm and a
compact prompt.

That is good enough to sit between the grammar and dictation stages, but not to be the primary
interpreter. Grammar must catch the exact phrases. The model handles loose phrasings. Anything it
calls `unclear` that still has content should escalate to Claude (P3-02) or trigger a
clarification. Summarisation works as a **fallback** for when Claude's `<spoken>` is missing.
Quality is clearly below `<spoken>`.

## Intent parsing — round 1 (ids 1–60)

| Schema | Prompt | Instr. tokens | Kind acc. | Kind+slots | Dangerous | p50 / p95 ms |
|---|---|---|---|---|---|---|
| A enum w/ assoc. values | plain | 568 | 50% | 50% | 1 | 1558 / 1808 |
| A | few-shot | 912 | 62% | 62% | 1 | 1842 / 2096 |
| A | context | 912 | 50% | 50% | 1 | 1953 / 2174 |
| **B flat kind + optional slots** | plain | 568 | 65% | 62% | 2 | **750** / 923 |
| B | few-shot | 912 | **75%** | 72% | 1 | 996 / 1186 |
| B | context | 912 | 73% | 73% | 1 | 1143 / 1321 |
| B | context + **prewarm** | 912 | 73% | 73% | 1 | **817** / 968 |
| B | context, streamed | 912 | 73% | 73% | 1 | kind known 1007, done 1161 |
| B | **tools** (findTab/findIssue) | 949 | 43% | 35% | 0 | 1613 / **21207** (8 context overflows) |
| B | context ×3 runs | 912 | 73% | 73% | 3 (=1×3) | 1141 / 1304; **0/60 unstable** |

Breakdown for B + context by category: clean 100%, ambiguous 100%, loose 62%, dictation 80%,
dictation traps 0% (e.g. "next we need to update the changelog" → `nextTab`), spoken issue keys
0%.

## Round 2: tuning vs hold-out (all 83, B/C, context)

| Variant | Tuning 1–60 | **Hold-out 61–83** | All | Wrong action | Dangerous | p50 / p95 ms |
|---|---|---|---|---|---|---|
| B context (baseline) | 73% | **70%** | 72% | 8 | 1 | 1151 / 1325 |
| B context + issue-key normaliser | 73% | 70% | 72% | 10 | 1 | 1156 / 1319 |
| B v2 prompt + normaliser | **83%** | **70%** | 80% | 9 | 1 | 1382 / 1594 |
| C (B without confidence) v2 + normaliser | 80% | 65% | 76% | 12 | 1 | 1325 / 1573 |
| C v2 + normaliser + prewarm | 80% | 65% | 76% | 12 | 1 | **805** / 1049 |

v2 adds per-command voice phrases (as the command registry will have), rewritten rules ("code
work is dictation even if it starts with next/open/stop", "unclear only if no reasonable
reading"), and the same examples. It gained 10 points on the tuning set and **nothing on the
hold-out**. Prompt tuning on this model overfits. Plan for a ceiling of ~70–80% on loose
phrasings, not for a prompt that fixes it.

Latency in `results/intents-r2-*` is contaminated by background system load after Apple
Intelligence was first enabled (C v2 p50 6.1 s; summaries 4 s). Round 3 (`r3-*`) re-ran the same
configurations back to back with a control. Accuracy was identical (greedy decoding is
deterministic) and latency was normal. The numbers above are from round 3.

### What the errors look like

- **Over-cautious `unclear`** (most common, safe): "no don't let it do that", "cancel what Claude
  is doing", "do I have any meetings tomorrow", "flip to the calendar", "nope, block that
  command".
- **Wrong command** (~10%): "show me my tasks" → `searchDocs`/`whereAmI`; "go one tab to the
  right" → `switchTab web-app`; "bring up ENG-98" → `searchDocs`; "let me see the changes in
  token tests" → `whatChanged`.
- **Dictation traps:** a verb that is also a command steals the utterance: "next we need…" →
  `nextTab`, "open a pull request…" → `openIssue`, **"approve the PR once CI passes" →
  `approve`** (the only dangerous error; deterministic in every configuration).
- **Spoken issue keys:** the model rarely resolves "eng one forty two" by itself. The
  deterministic normaliser (`Normalise.swift`) turns it into ENG-142, but even then the model
  sometimes picks `unclear` or `searchDocs`.

### Things that didn't work

- **Tool calling:** the model calls a tool on **every** utterance (findTab("uh"), findTab("yes")),
  and the tool output biases it towards `switchTab`. 8 of 60 looped on tool calls until
  `exceededContextWindowSize` after ~20 s. Accuracy fell to 43%. *Inject context into the prompt;
  no tools in the router.*
- **Self-reported confidence:** almost everything is 0.8–0.95. In the 0.5–0.8 bucket 40% were
  right, in 0.8–0.95 78% were right. That's not usable for thresholds. Dropping the field (schema
  C) did not speed things up measurably, but it did change outputs and cost 5 points on the
  hold-out. *Use `unclear` as the confidence signal, not a number.*
- **Enum with associated values (schema A):** 11–23 points worse and ~1.7× slower than the flat
  schema.
- **Long-utterance rule** ("≥7 words is dictation unless it names an issue"): simulated over the
  results, it made things worse (−6 to −8 points), because many loose commands are long.
- **Streaming:** the kind is known ~150 ms before the full answer. That isn't worth the
  complexity.

### Guardrails (gotcha)

With schema C and the v2 prompt, the default guardrails reject **"switch to the API", "diff of the
readme" and "abort, abort"** with `guardrailViolation`, deterministically. Schema B with the same
prompt doesn't. `.permissiveContentTransformations` does not help for guided generation. The
router must treat `guardrailViolation`, `refusal` and `decodingFailure` as "no parse" and fall
through (to grammar retry → Claude → clarify). It must never surface them as errors.

### Latency notes

- Prompt size costs ~1 ms per instruction token (568 → 912 tokens: 750 → ~1000–1150 ms). P2-05
  generates the catalog from the command registry, so it should include **only commands
  available in the current context** (focused tab kind + globals) to keep the prompt small as
  modules are added.
- `session.prewarm()` at push-to-talk press, plus ≥1 s of speech, saves ~330–500 ms. The first
  call in a process costs about the same as later ones (the model lives in a system service).
  Right after Apple Intelligence was enabled, the first call took 2.8 s.
- Background system load can multiply latency by 4–5×, as round 2 showed. **Hard timeouts are
  essential:** ~1.5 s for intent, then fall through.

## Summarisation (9 turns from the P0-04 fixtures)

| Variant | p50 / max ms | Words | Problems |
|---|---|---|---|
| v1: plain `respond`, raw reply text | 560 / 1820 | 15–89 | echoed a markdown table verbatim; 89 words for the session recap; backticks and quotes kept; "Sure, here's a summary…" preamble |
| v2: replace code/tables with notes, strip markdown, guided `Spoken` + `maximumResponseTokens: 90` | 710 / 1100 | 20–38 | no markdown; 1 `decodingFailure` (input was nothing but a table); dangling "with this haiku:"; reads hashes like "cfc22b5"; recap dropped most items |
| Claude `<spoken>` (reference, P0-04) | (part of the turn) | 16–40 | — clearly the best: natural, complete, speakable |

- Guardrails: no violations on any turn with either setting. Code, shell commands and `rm` were
  fine.
- Context window: a 2,401-token digest succeeded but took **6.3 s**, because the output was long.
  Overflowing inputs fail fast (`exceededContextWindowSize` in 0.8–1.2 s). Budget the digest to
  ~1,500 tokens (`tokenCount(for:)`, macOS 26.4+) and cap the response.
- **Recommendation:** keep `<spoken>` as the primary source (45/45 compliance in P0-04). Use the
  on-device v2 pipeline only when it is missing, with a post-filter (strip `#`, backticks, hex
  hashes) and a deterministic fallback (first sentence of the speakable reply) on any error.

## Recommendations for P2-05 / DESIGN §3.4, §4.6 (proposed in ADR 0003)

1. **Routing:** grammar (exact registered phrases, with typed slots, after deterministic
   normalisation of issue keys and numbers) → on-device intent (flat `kind` + optional slots
   schema, context injected, catalog limited to the current context, greedy, 1.5 s timeout,
   prewarmed at activation) → result handling:
   - a command kind → execute under its risk tier. **Risky kinds from the model stage always
     confirm**, even reversible ones, because the model is where "approve the PR…" came from.
   - `dictation` / `askAgent` → send the **raw utterance** (minus a deterministic "tell Claude
     to" prefix). The model paraphrases free-text slots despite instructions.
   - `unclear`, a timeout or "no parse" → if the utterance has content (≥3 words): Claude
     escalation (P3-02) when available, else a clarifying question. Otherwise "didn't catch
     that".
2. **Ignore slots the chosen command doesn't declare.** The model fills them with context values
   (e.g. `nextTab` with `tab=web-app`).
3. **No tools, no confidence field, no streaming** in the intent call.
4. **P2-05 acceptance thresholds** (proposal for P0-06):
   - grammar stage <50 ms
   - full routing (grammar + model + rules) ≥90% on clean, ≥75% on loose and hold-out
   - **0 unconfirmed dangerous actions**
   - wrong-action rate ≤10%
   - model p50 ≤1.0 s with prewarm

   Accuracy above ~80% on loose phrasings needs the Claude fallback, not prompt work.
5. **Claude fallback (measure in P3-02):** P0-04 measured a Haiku turn via the CLI at ~0.9 s. A
   direct API call should be comparable to the on-device model. Worth evaluating then as a
   *parallel* or *second* interpreter for `unclear` results. The on-device model stays the
   private, offline, free default.
6. `vocoder doctor` checks `SystemLanguageModel.default.availability` and explains
   `appleIntelligenceNotEnabled` (it was off on this machine at first).

## Other gotchas

- `tokenCount(for:)` needs macOS 26.4. The spike sets `platforms: [.macOS("26.4")]`.
- `PrivateCloudComputeLanguageModel` exists in the SDK but is **macOS 27+** (not usable on
  26.6). `GenerationOptions.toolCallingMode` is also 27+.
- `@Generable` enums with associated values work, but they're slower and less accurate than a
  flat struct with a simple enum `kind`.
- In the language mode used here, `Tool.call` is `@concurrent`. A `Sendable` tool struct holding
  a lock-protected log works fine.
