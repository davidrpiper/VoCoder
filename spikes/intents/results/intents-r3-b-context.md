### r3-b-context

schema=b prompt=context prewarm=false stream=false permissive=false normalise=false runs=1 n=83 instructionTokens=912

| Metric | Value |
|---|---|
| Kind accuracy | 72% |
| Kind + slots | 72% |
| Dangerous errors (risky kind chosen wrongly) | 1 |
| Errors thrown | 0 |
| First call (incl. load) | 1175 ms |
| Latency p50 / p95 / max (rest) | 1151 / 1325 / 1788 ms |

| Set | n | kind | kind+slots | wrong action (not unclear) | dangerous |
|---|---|---|---|---|---|
| tuning 1–60 | 60 | 73% | 73% | 6 | 1 |
| hold-out 61+ | 23 | 70% | 70% | 2 | 0 |
| all | 83 | 72% | 72% | 8 | 1 |

| Category | n | kind | kind+slots |
|---|---|---|---|
| ambiguous | 7 | 100% | 100% |
| clean | 20 | 100% | 100% |
| dictation | 5 | 80% | 80% |
| dictation-trap | 4 | 0% | 0% |
| holdout-ambiguous | 2 | 100% | 100% |
| holdout-clean | 6 | 83% | 83% |
| holdout-dictation | 3 | 67% | 67% |
| holdout-loose | 11 | 64% | 64% |
| holdout-spoken-form | 1 | 0% | 0% |
| loose | 21 | 62% | 62% |
| out-of-schema | 1 | 0% | 0% |
| spoken-form | 2 | 0% | 0% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 1 | 100% |
| [0.50, 0.80) | 16 | 44% |
| [0.80, 0.95) | 62 | 77% |
| [0.95, 1.00) | 4 | 100% |

Failures:
- 7 "show me my tasks" → searchDocs ["query": "tasks"] (expected switchTab)
- 11 "sorry what was that" → unclear ["text": "sorry what was that"] (expected repeatLast)
- 14 "no don't let it do that" → unclear ["text": "no don\'t let it do that"] (expected deny)
- 16 "cancel what Claude is doing" → unclear ["text": "cancel what Claude is doing"] (expected interruptAgent)
- 17 "hold on, kill that, stop the agent" → unclear [:] (expected interruptAgent)
- 27 "pull up ticket eng one forty two" → unclear [:] (expected openIssue)
- 28 "go to issue E N G one two three" → unclear [:] (expected openIssue)
- 34 "let's pick up the Safari login bug" → dictation ["text": "let\'s pick up the Safari login bug"] (expected startWorkingOn)
- 35 "what did the last comment on my auth ticket say" → readLastResponse ["text": "token refresh in auth service", "issue": "ENG-142"] (expected unclear|openIssue)
- 39 "do I have any meetings tomorrow" → unclear [:] (expected agenda)
- 45 "why is this test flaky" → unclear [:] (expected dictation|askAgent)
- 46 "next we need to update the changelog and bump the version" → nextTab ["tab": "docs"] (expected dictation|askAgent)
- 47 "open a pull request when you're done" → openIssue ["text": "open a pull request when you\'re done", "issue": "ENG-142"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → approve [:] (expected dictation|askAgent|unclear) **dangerous**
- 49 "stop using force unwraps in the parser" → unclear [:] (expected dictation|askAgent)
- 57 "what's the agent doing right now" → unclear [:] (expected readLastResponse|whereAmI)
- 61 "flip to the calendar" → unclear [:] (expected switchTab)
- 62 "go one tab to the right" → switchTab ["tab": "web-app"] (expected nextTab)
- 65 "nope, block that command" → unclear ["text": "block that command"] (expected deny)
- 69 "let me see the changes in token tests" → whatChanged ["issue": "ENG-142", "tab": "api"] (expected showDiff)
- 70 "bring up ENG-98" → unclear [:] (expected openIssue)
- 77 "stop the build from caching node modules" → unclear [:] (expected dictation|askAgent)
- 83 "pull up ticket eng ninety eight" → unclear [:] (expected openIssue)
