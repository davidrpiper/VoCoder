### a-plain

schema=a prompt=plain prewarm=false stream=false permissive=false runs=1 n=60 instructionTokens=568

| Metric | Value |
|---|---|
| Kind accuracy | 50% |
| Kind + slots | 50% |
| Dangerous errors (risky kind chosen wrongly) | 1 |
| Errors thrown | 0 |
| First call (incl. load) | 1548 ms |
| Latency p50 / p95 / max (rest) | 1558 / 1808 / 2012 ms |

| Category | n | kind | kind+slots |
|---|---|---|---|
| ambiguous | 7 | 43% | 43% |
| clean | 20 | 80% | 80% |
| dictation | 5 | 20% | 20% |
| dictation-trap | 4 | 0% | 0% |
| loose | 21 | 48% | 48% |
| out-of-schema | 1 | 0% | 0% |
| spoken-form | 2 | 0% | 0% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 1 | 100% |
| [0.50, 0.80) | 5 | 20% |
| [0.80, 0.95) | 54 | 52% |
| [0.95, 1.00) | 0 | - |

Failures:
- 7 "show me my tasks" → searchDocs ["query": "tasks"] (expected switchTab)
- 11 "sorry what was that" → unclear [:] (expected repeatLast)
- 13 "yeah go ahead and let it run that" → switchTab ["tab": "run"] (expected approve)
- 14 "no don't let it do that" → unclear [:] (expected deny)
- 16 "cancel what Claude is doing" → switchTab ["tab": "agent"] (expected interruptAgent)
- 17 "hold on, kill that, stop the agent" → unclear [:] (expected interruptAgent)
- 18 "what did Claude say" → whatChanged [:] (expected readLastResponse)
- 27 "pull up ticket eng one forty two" → switchTab ["tab": "ticket"] (expected openIssue)
- 28 "go to issue E N G one two three" → switchTab ["tab": "issue"] (expected openIssue)
- 29 "move ENG-123 to in review" → switchTab ["tab": "in review"] (expected setIssueStatus)
- 30 "mark this ticket as done" → switchTab ["tab": "ticket"] (expected setIssueStatus)
- 32 "reply on the ticket: looks good to me" → switchTab ["tab": "ticket"] (expected commentOnIssue)
- 34 "let's pick up the Safari login bug" → switchTab ["tab": "login"] (expected startWorkingOn)
- 35 "what did the last comment on my auth ticket say" → searchDocs ["query": "auth ticket"] (expected unclear|openIssue)
- 38 "what's on my calendar today" → searchDocs ["query": "today"] (expected agenda)
- 39 "do I have any meetings tomorrow" → searchDocs ["query": "meetings tomorrow"] (expected agenda)
- 41 "the token refresh fails when the clock skews by more than five minutes, can you add some leeway" → switchTab ["tab": "repo"] (expected dictation|askAgent)
- 42 "refactor the user service to use async await" → switchTab ["tab": "repo"] (expected dictation|askAgent)
- 43 "I think we should rename this function to fetch user" → switchTab ["tab": "fetchUser"] (expected dictation|askAgent)
- 45 "why is this test flaky" → whatChanged [:] (expected dictation|askAgent)
- 46 "next we need to update the changelog and bump the version" → switchTab ["tab": "changelog"] (expected dictation|askAgent)
- 47 "open a pull request when you're done" → openIssue ["issue": "ENG-123"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → approve [:] (expected dictation|askAgent|unclear) **dangerous**
- 49 "stop using force unwraps in the parser" → switchTab ["tab": "parser"] (expected dictation|askAgent)
- 52 "the other one" → switchTab ["tab": "other"] (expected unclear)
- 53 "move it" → switchTab ["tab": "repo"] (expected unclear)
- 54 "can you check on that" → switchTab ["tab": "repo"] (expected unclear)
- 57 "what's the agent doing right now" → whatChanged [:] (expected readLastResponse|whereAmI)
- 58 "read it" → unclear [:] (expected readLastResponse|repeatLast)
- 59 "yes" → switchTab ["tab": "repo"] (expected approve|unclear)
