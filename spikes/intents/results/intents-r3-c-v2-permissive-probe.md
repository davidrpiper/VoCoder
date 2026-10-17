### r3-c-v2-permissive-probe

schema=c prompt=v2 prewarm=false stream=false permissive=true normalise=true runs=1 n=5 instructionTokens=1215

| Metric | Value |
|---|---|
| Kind accuracy | 20% |
| Kind + slots | 20% |
| Dangerous errors (risky kind chosen wrongly) | 1 |
| Errors thrown | 3 |
| First call (incl. load) | 1273 ms |
| Latency p50 / p95 / max (rest) | 1338 / 1454 / 1454 ms |

| Set | n | kind | kind+slots | wrong action (not unclear) | dangerous |
|---|---|---|---|---|---|
| tuning 1–60 | 4 | 25% | 25% | 1 | 1 |
| hold-out 61+ | 1 | 0% | 0% | 0 | 0 |
| all | 5 | 20% | 20% | 1 | 1 |

| Category | n | kind | kind+slots |
|---|---|---|---|
| clean | 2 | 50% | 50% |
| dictation-trap | 1 | 0% | 0% |
| holdout-loose | 1 | 0% | 0% |
| loose | 1 | 0% | 0% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 0 | - |
| [0.50, 0.80) | 0 | - |
| [0.80, 0.95) | 0 | - |
| [0.95, 1.00) | 0 | - |

Failures:
- 3 "switch to the API" → guardrailViolation (expected switchTab)
- 25 "diff of the readme" → guardrailViolation (expected showDiff)
- 48 "approve the PR once CI passes" → approve ["text": "approve the PR once CI passes"] (expected dictation|askAgent|unclear) **dangerous**
- 66 "abort, abort" → guardrailViolation (expected interruptAgent|unclear)
