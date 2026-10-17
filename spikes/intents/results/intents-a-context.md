### a-context

schema=a prompt=context prewarm=false stream=false permissive=false runs=1 n=60 instructionTokens=912

| Metric | Value |
|---|---|
| Kind accuracy | 50% |
| Kind + slots | 50% |
| Dangerous errors (risky kind chosen wrongly) | 1 |
| Errors thrown | 0 |
| First call (incl. load) | 1866 ms |
| Latency p50 / p95 / max (rest) | 1953 / 2174 / 2422 ms |

| Category | n | kind | kind+slots |
|---|---|---|---|
| ambiguous | 7 | 43% | 43% |
| clean | 20 | 70% | 70% |
| dictation | 5 | 40% | 40% |
| dictation-trap | 4 | 0% | 0% |
| loose | 21 | 52% | 52% |
| out-of-schema | 1 | 0% | 0% |
| spoken-form | 2 | 0% | 0% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 1 | 100% |
| [0.50, 0.80) | 8 | 50% |
| [0.80, 0.95) | 51 | 49% |
| [0.95, 1.00) | 0 | - |

Failures:
- 2 "go to the previous tab" → switchTab ["tab": "web-app"] (expected previousTab)
- 7 "show me my tasks" → searchDocs ["query": "tasks"] (expected switchTab)
- 11 "sorry what was that" → unclear [:] (expected repeatLast)
- 13 "yeah go ahead and let it run that" → switchTab ["tab": "api"] (expected approve)
- 14 "no don't let it do that" → unclear [:] (expected deny)
- 16 "cancel what Claude is doing" → switchTab ["tab": "tasks"] (expected interruptAgent)
- 17 "hold on, kill that, stop the agent" → unclear [:] (expected interruptAgent)
- 18 "what did Claude say" → whereAmI [:] (expected readLastResponse)
- 26 "open ENG-123" → switchTab ["tab": "web-app"] (expected openIssue)
- 27 "pull up ticket eng one forty two" → switchTab ["tab": "ticket"] (expected openIssue)
- 28 "go to issue E N G one two three" → switchTab ["tab": "ENG-142"] (expected openIssue)
- 29 "move ENG-123 to in review" → switchTab ["tab": "in review"] (expected setIssueStatus)
- 32 "reply on the ticket: looks good to me" → askAgent ["text": "reply on the ticket: looks good to me"] (expected commentOnIssue)
- 34 "let's pick up the Safari login bug" → switchTab ["tab": "web-app"] (expected startWorkingOn)
- 35 "what did the last comment on my auth ticket say" → whereAmI [:] (expected unclear|openIssue)
- 38 "what's on my calendar today" → searchDocs ["query": "today"] (expected agenda)
- 39 "do I have any meetings tomorrow" → unclear [:] (expected agenda)
- 40 "what's next on my schedule" → unclear [:] (expected agenda)
- 42 "refactor the user service to use async await" → switchTab ["tab": "user-service"] (expected dictation|askAgent)
- 43 "I think we should rename this function to fetch user" → switchTab ["tab": "api"] (expected dictation|askAgent)
- 45 "why is this test flaky" → whatChanged [:] (expected dictation|askAgent)
- 46 "next we need to update the changelog and bump the version" → switchTab ["tab": "docs"] (expected dictation|askAgent)
- 47 "open a pull request when you're done" → switchTab ["tab": "pull-requests"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → approve [:] (expected dictation|askAgent|unclear) **dangerous**
- 49 "stop using force unwraps in the parser" → switchTab ["tab": "api"] (expected dictation|askAgent)
- 52 "the other one" → switchTab ["tab": "web-app"] (expected unclear)
- 53 "move it" → switchTab ["tab": "tasks"] (expected unclear)
- 54 "can you check on that" → whereAmI [:] (expected unclear)
- 58 "read it" → unclear [:] (expected readLastResponse|repeatLast)
- 59 "yes" → switchTab ["tab": "api"] (expected approve|unclear)
