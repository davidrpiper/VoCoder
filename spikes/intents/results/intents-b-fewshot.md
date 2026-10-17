### b-fewshot

schema=b prompt=fewshot prewarm=false stream=false permissive=false runs=1 n=60 instructionTokens=912

| Metric | Value |
|---|---|
| Kind accuracy | 75% |
| Kind + slots | 72% |
| Dangerous errors (risky kind chosen wrongly) | 1 |
| Errors thrown | 0 |
| First call (incl. load) | 1244 ms |
| Latency p50 / p95 / max (rest) | 996 / 1186 / 1258 ms |

| Category | n | kind | kind+slots |
|---|---|---|---|
| ambiguous | 7 | 100% | 100% |
| clean | 20 | 95% | 95% |
| dictation | 5 | 80% | 80% |
| dictation-trap | 4 | 50% | 50% |
| loose | 21 | 57% | 48% |
| out-of-schema | 1 | 100% | 100% |
| spoken-form | 2 | 0% | 0% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 1 | 100% |
| [0.50, 0.80) | 11 | 45% |
| [0.80, 0.95) | 47 | 81% |
| [0.95, 1.00) | 1 | 100% |

Failures:
- 7 "show me my tasks" → searchDocs ["query": "tasks"] (expected switchTab)
- 11 "sorry what was that" → unclear [:] (expected repeatLast)
- 13 "yeah go ahead and let it run that" → unclear [:] (expected approve)
- 14 "no don't let it do that" → unclear [:] (expected deny)
- 17 "hold on, kill that, stop the agent" → unclear [:] (expected interruptAgent)
- 24 "show me the diff for the auth service" → showDiff ["tab": "auth service"] (expected showDiff)
- 25 "diff of the readme" → showDiff ["tab": "docs", "issue": "readme"] (expected showDiff)
- 27 "pull up ticket eng one forty two" → unclear [:] (expected openIssue)
- 28 "go to issue E N G one two three" → unclear [:] (expected openIssue)
- 32 "reply on the ticket: looks good to me" → askAgent ["text": "reply on the ticket: looks good to me"] (expected commentOnIssue)
- 34 "let's pick up the Safari login bug" → dictation ["text": "let\'s pick up the Safari login bug"] (expected startWorkingOn)
- 39 "do I have any meetings tomorrow" → unclear [:] (expected agenda)
- 45 "why is this test flaky" → unclear [:] (expected dictation|askAgent)
- 47 "open a pull request when you're done" → openIssue ["issue": "ENG-123"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → approve [:] (expected dictation|askAgent|unclear) **dangerous**
- 57 "what's the agent doing right now" → unclear [:] (expected readLastResponse|whereAmI)
- 58 "read it" → unclear [:] (expected readLastResponse|repeatLast)
