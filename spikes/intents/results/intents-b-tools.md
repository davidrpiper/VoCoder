### b-tools

schema=b prompt=tools prewarm=false stream=false permissive=false runs=1 n=60 instructionTokens=949

| Metric | Value |
|---|---|
| Kind accuracy | 43% |
| Kind + slots | 35% |
| Dangerous errors (risky kind chosen wrongly) | 0 |
| Errors thrown | 8 |
| First call (incl. load) | 1560 ms |
| Latency p50 / p95 / max (rest) | 1613 / 21207 / 23116 ms |
| Rows with tool calls | 60 |

| Category | n | kind | kind+slots |
|---|---|---|---|
| ambiguous | 7 | 0% | 0% |
| clean | 20 | 70% | 50% |
| dictation | 5 | 60% | 60% |
| dictation-trap | 4 | 0% | 0% |
| loose | 21 | 43% | 38% |
| out-of-schema | 1 | 0% | 0% |
| spoken-form | 2 | 0% | 0% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 0 | - |
| [0.50, 0.80) | 6 | 0% |
| [0.80, 0.95) | 31 | 48% |
| [0.95, 1.00) | 15 | 73% |

Failures:
- 4 "tab three" → switchTab ["tab": "api"] (expected switchTab)
- 11 "sorry what was that" → unclear ["query": "sorry", "tab": "api"] (expected repeatLast)
- 12 "approve" → exceededContextWindowSize (expected approve)
- 13 "yeah go ahead and let it run that" → switchTab ["tab": "api"] (expected approve)
- 14 "no don't let it do that" → unclear ["text": "no don\'t let it do that", "tab": "api"] (expected deny)
- 15 "reject" → switchTab ["tab": "api"] (expected deny)
- 16 "cancel what Claude is doing" → unclear ["issue": "ENG-142", "tab": "api"] (expected interruptAgent)
- 17 "hold on, kill that, stop the agent" → unclear ["tab": "api", "issue": "ENG-142"] (expected interruptAgent)
- 21 "ask the agent why the build is failing" → askAgent [:] (expected askAgent|dictation)
- 23 "which files did it touch" → exceededContextWindowSize (expected whatChanged)
- 24 "show me the diff for the auth service" → showDiff ["issue": "ENG-142", "tab": "api"] (expected showDiff)
- 26 "open ENG-123" → exceededContextWindowSize (expected openIssue)
- 27 "pull up ticket eng one forty two" → unclear [:] (expected openIssue)
- 28 "go to issue E N G one two three" → unclear [:] (expected openIssue)
- 29 "move ENG-123 to in review" → exceededContextWindowSize (expected setIssueStatus)
- 30 "mark this ticket as done" → unclear [:] (expected setIssueStatus)
- 31 "comment on ENG-98 saying the fix is deployed to staging" → exceededContextWindowSize (expected commentOnIssue)
- 32 "reply on the ticket: looks good to me" → unclear [:] (expected commentOnIssue)
- 33 "start working on ENG-77" → startWorkingOn ["text": "Start work on the current issue ENG-142.", "issue": "ENG-142"] (expected startWorkingOn)
- 34 "let's pick up the Safari login bug" → switchTab ["tab": "api"] (expected startWorkingOn)
- 35 "what did the last comment on my auth ticket say" → exceededContextWindowSize (expected unclear|openIssue)
- 37 "find the notion page about the release process" → switchTab ["tab": "api"] (expected searchDocs)
- 39 "do I have any meetings tomorrow" → unclear ["day": "tomorrow", "tab": "api"] (expected agenda)
- 40 "what's next on my schedule" → switchTab ["tab": "tasks"] (expected agenda)
- 41 "the token refresh fails when the clock skews by more than five minutes, can you add some leeway" → exceededContextWindowSize (expected dictation|askAgent)
- 45 "why is this test flaky" → unclear [:] (expected dictation|askAgent)
- 46 "next we need to update the changelog and bump the version" → switchTab ["tab": "changelog"] (expected dictation|askAgent)
- 47 "open a pull request when you're done" → unclear ["tab": "api", "issue": "ENG-142"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → exceededContextWindowSize (expected dictation|askAgent|unclear)
- 49 "stop using force unwraps in the parser" → switchTab ["tab": "parser"] (expected dictation|askAgent)
- 50 "do the thing" → switchTab ["tab": "api"] (expected unclear)
- 51 "uh" → switchTab ["tab": "api"] (expected unclear)
- 52 "the other one" → switchTab ["tab": "api"] (expected unclear)
- 53 "move it" → switchTab ["tab": "api"] (expected unclear)
- 54 "can you check on that" → switchTab ["tab": "api"] (expected unclear)
- 55 "status" → switchTab ["tab": "api"] (expected unclear|whatChanged|whereAmI)
- 56 "switch to tab number five" → switchTab ["tab": "api"] (expected switchTab)
- 58 "read it" → switchTab ["tab": "api"] (expected readLastResponse|repeatLast)
- 59 "yes" → switchTab ["tab": "api"] (expected approve|unclear)
