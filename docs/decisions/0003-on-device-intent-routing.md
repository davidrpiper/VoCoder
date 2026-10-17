# 0003 — On-device intent parsing as a guarded middle stage

- Status: Accepted (confirmed in P0-06)
- Date: 2026-10-17
- WP: P0-05

## Context

DESIGN §3.4/§4.6 planned three-stage routing: grammar → on-device Foundation Models intent parse
(guided generation into a `@Generable Intent`) → dictation, with low-confidence results triggering
a clarifying question. Open risk §8 #4 targeted <1 s for intent parsing. The spike
(`spikes/intents/`, see its FINDINGS.md) measured 20 intents over 83 labelled utterances, 23 of
them a hold-out set.

Evidence:
- Flat schema (simple `kind` enum + optional slots) beat an enum with associated values by
  11–23 points and was ~1.7× faster.
- Accuracy: clean phrasings 100%, vague ones correctly `unclear` 100%. Loose phrasings ~65–80%,
  hold-out 70%. Prompt tuning gained +10 points on the tuning set and 0 on the hold-out. Most
  misses are `unclear` (safe). Wrong actions happen on ~10% of utterances. One deterministic
  dangerous error: "approve the PR once CI passes" → `approve`.
- Latency p50 ~1.15 s, ~0.8 s with `prewarm()` at activation. Roughly 1 ms per instruction
  token. Background load can cause 4–5× spikes.
- Self-reported confidence is uncalibrated (0.8–0.95 for nearly everything). Tool calling is
  harmful: tools are called on every utterance and some calls loop to context overflow after
  ~20 s.
- The default guardrails deterministically reject some benign utterances ("switch to the API")
  for some schemas, and permissive guardrails don't apply to guided generation.
- The model paraphrases free-text slots despite instructions.
- On-device summaries of agent turns are usable only after pre-processing (code and tables
  replaced by notes, markdown stripped, guided output, token cap). They are clearly worse than
  Claude's `<spoken>`.

## Decision

- **Keep the on-device model as the middle routing stage**, not as the primary interpreter.
  Grammar handles exact registered phrases after deterministic normalisation (spoken issue keys,
  numbers).
- Intent call shape: flat `kind` + optional typed slots; the catalog is generated from the
  command registry and **limited to commands available in the current context**; app context is
  injected into the prompt; greedy sampling; `prewarm()` on activation; hard timeout ~1.5 s.
  **No tools, no confidence field, no streaming.**
- **Confidence = the `unclear` kind**, not a score. `unclear`, a timeout, `guardrailViolation`,
  `refusal` and `decodingFailure` all mean "no parse". Utterances with content escalate to the
  Claude `LanguageModel` (P3-02) when available. Otherwise VoCoder asks back.
- **Risky kinds from the model stage always require confirmation**, even when the command's own
  tier is lower. (Risky kinds: approve, deny, status change, comment, start work, interrupt.)
- Dictation and `askAgent` pass the **raw utterance** on (minus a deterministic addressing
  prefix), never the model's slot text. Slots the chosen command doesn't declare are ignored.
- Spoken agent summaries: Claude's `<spoken>` is primary. The on-device pipeline is a fallback,
  with an input budget of ~1,500 tokens (`tokenCount`), a response cap, a post-filter, and a
  deterministic first-sentence fallback.

## Consequences

- Loose-phrasing accuracy above ~80% depends on the Claude fallback (P3-02), not prompt work.
  Until then (Phase 2), more utterances end in a clarifying question.
- `LanguageModel` protocol needs: availability, prewarm, guided generation with a timeout, and a
  typed "no parse" outcome. Contract tests cover the error-to-no-parse mapping.
- Deployment target rises to **macOS 26.4** (`tokenCount`).
- `vocoder doctor` checks Apple Intelligence availability.
- DESIGN §3.4, §4.6 and §8 #4 updated. PLAN P2-05 scope and acceptance updated; P3-02 evaluates
  Claude as the second interpreter.

## Alternatives considered

- **Model as primary interpreter, confidence thresholds:** confidence is uncalibrated and loose
  accuracy too low.
- **Tool calling for context resolution:** slower, less accurate, loops.
- **Enum with associated values schema:** slower and less accurate.
- **Length heuristic for dictation:** simulated, made accuracy worse.
- **Private Cloud Compute model:** macOS 27+ only. Revisit when the machine is on 27.
