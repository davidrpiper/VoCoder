### a-fewshot

schema=a prompt=fewshot prewarm=false stream=false permissive=false runs=1 n=60 instructionTokens=912

| Metric | Value |
|---|---|
| Kind accuracy | 62% |
| Kind + slots | 62% |
| Dangerous errors (risky kind chosen wrongly) | 1 |
| Errors thrown | 0 |
| First call (incl. load) | 1757 ms |
| Latency p50 / p95 / max (rest) | 1842 / 2096 / 2286 ms |

| Category | n | kind | kind+slots |
|---|---|---|---|
| ambiguous | 7 | 71% | 71% |
| clean | 20 | 90% | 90% |
| dictation | 5 | 40% | 40% |
| dictation-trap | 4 | 0% | 0% |
| loose | 21 | 57% | 57% |
| out-of-schema | 1 | 0% | 0% |
| spoken-form | 2 | 0% | 0% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 1 | 100% |
| [0.50, 0.80) | 4 | 75% |
| [0.80, 0.95) | 54 | 59% |
| [0.95, 1.00) | 1 | 100% |

Failures:
- 2 "go to the previous tab" → switchTab ["tab": "previous"] (expected previousTab)
- 7 "show me my tasks" → searchDocs ["query": "tasks"] (expected switchTab)
- 11 "sorry what was that" → unclear [:] (expected repeatLast)
- 13 "yeah go ahead and let it run that" → switchTab ["tab": "run"] (expected approve)
- 14 "no don't let it do that" → unclear [:] (expected deny)
- 16 "cancel what Claude is doing" → unclear [:] (expected interruptAgent)
- 17 "hold on, kill that, stop the agent" → unclear [:] (expected interruptAgent)
- 27 "pull up ticket eng one forty two" → switchTab ["tab": "ticket"] (expected openIssue)
- 28 "go to issue E N G one two three" → switchTab ["tab": "ENG-123"] (expected openIssue)
- 32 "reply on the ticket: looks good to me" → askAgent ["text": "reply on the ticket: looks good to me"] (expected commentOnIssue)
- 34 "let's pick up the Safari login bug" → switchTab ["tab": "bug"] (expected startWorkingOn)
- 35 "what did the last comment on my auth ticket say" → whatChanged [:] (expected unclear|openIssue)
- 39 "do I have any meetings tomorrow" → searchDocs ["query": "meetings tomorrow"] (expected agenda)
- 41 "the token refresh fails when the clock skews by more than five minutes, can you add some leeway" → whatChanged [:] (expected dictation|askAgent)
- 43 "I think we should rename this function to fetch user" → switchTab ["tab": "fetchUser"] (expected dictation|askAgent)
- 45 "why is this test flaky" → whatChanged [:] (expected dictation|askAgent)
- 46 "next we need to update the changelog and bump the version" → switchTab ["tab": "changelog"] (expected dictation|askAgent)
- 47 "open a pull request when you're done" → openIssue ["issue": "ENG-12"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → approve [:] (expected dictation|askAgent|unclear) **dangerous**
- 49 "stop using force unwraps in the parser" → switchTab ["tab": "parser"] (expected dictation|askAgent)
- 52 "the other one" → switchTab ["tab": "other"] (expected unclear)
- 58 "read it" → unclear [:] (expected readLastResponse|repeatLast)
- 59 "yes" → switchTab [:] (expected approve|unclear)
