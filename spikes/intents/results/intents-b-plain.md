### b-plain

schema=b prompt=plain prewarm=false stream=false permissive=false runs=1 n=60 instructionTokens=568

| Metric | Value |
|---|---|
| Kind accuracy | 65% |
| Kind + slots | 62% |
| Dangerous errors (risky kind chosen wrongly) | 2 |
| Errors thrown | 0 |
| First call (incl. load) | 781 ms |
| Latency p50 / p95 / max (rest) | 750 / 923 / 1123 ms |

| Category | n | kind | kind+slots |
|---|---|---|---|
| ambiguous | 7 | 86% | 86% |
| clean | 20 | 85% | 85% |
| dictation | 5 | 60% | 60% |
| dictation-trap | 4 | 0% | 0% |
| loose | 21 | 57% | 48% |
| out-of-schema | 1 | 0% | 0% |
| spoken-form | 2 | 50% | 50% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 1 | 100% |
| [0.50, 0.80) | 8 | 75% |
| [0.80, 0.95) | 47 | 60% |
| [0.95, 1.00) | 4 | 100% |

Failures:
- 7 "show me my tasks" → searchDocs ["query": "tasks"] (expected switchTab)
- 11 "sorry what was that" → unclear [:] (expected repeatLast)
- 13 "yeah go ahead and let it run that" → switchTab ["tab": "repo"] (expected approve)
- 14 "no don't let it do that" → unclear [:] (expected deny)
- 16 "cancel what Claude is doing" → unclear [:] (expected interruptAgent)
- 17 "hold on, kill that, stop the agent" → unclear [:] (expected interruptAgent)
- 18 "what did Claude say" → repeatLast [:] (expected readLastResponse)
- 24 "show me the diff for the auth service" → showDiff ["tab": "auth service"] (expected showDiff)
- 25 "diff of the readme" → showDiff ["issue": "README", "tab": "docs"] (expected showDiff)
- 28 "go to issue E N G one two three" → unclear [:] (expected openIssue)
- 29 "move ENG-123 to in review" → switchTab ["tab": "in review"] (expected setIssueStatus)
- 30 "mark this ticket as done" → approve [:] (expected setIssueStatus) **dangerous**
- 32 "reply on the ticket: looks good to me" → askAgent ["text": "reply on the ticket: looks good to me"] (expected commentOnIssue)
- 34 "let's pick up the Safari login bug" → searchDocs ["query": "Safari login bug"] (expected startWorkingOn)
- 35 "what did the last comment on my auth ticket say" → searchDocs ["query": "auth ticket"] (expected unclear|openIssue)
- 41 "the token refresh fails when the clock skews by more than five minutes, can you add some leeway" → unclear [:] (expected dictation|askAgent)
- 45 "why is this test flaky" → unclear [:] (expected dictation|askAgent)
- 46 "next we need to update the changelog and bump the version" → nextTab ["tab": "changelog"] (expected dictation|askAgent)
- 47 "open a pull request when you're done" → openIssue ["issue": "ENG-123"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → approve [:] (expected dictation|askAgent|unclear) **dangerous**
- 49 "stop using force unwraps in the parser" → unclear [:] (expected dictation|askAgent)
- 58 "read it" → unclear [:] (expected readLastResponse|repeatLast)
- 59 "yes" → switchTab ["tab": "repo1"] (expected approve|unclear)
