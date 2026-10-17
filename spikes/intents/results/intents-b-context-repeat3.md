### b-context-repeat3

schema=b prompt=context prewarm=false stream=false permissive=false runs=3 n=180 instructionTokens=912

| Metric | Value |
|---|---|
| Kind accuracy | 73% |
| Kind + slots | 73% |
| Dangerous errors (risky kind chosen wrongly) | 3 |
| Errors thrown | 0 |
| First call (incl. load) | 1120 ms |
| Latency p50 / p95 / max (rest) | 1141 / 1304 / 1366 ms |

| Category | n | kind | kind+slots |
|---|---|---|---|
| ambiguous | 21 | 100% | 100% |
| clean | 60 | 100% | 100% |
| dictation | 15 | 80% | 80% |
| dictation-trap | 12 | 0% | 0% |
| loose | 63 | 62% | 62% |
| out-of-schema | 3 | 0% | 0% |
| spoken-form | 6 | 0% | 0% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 3 | 100% |
| [0.50, 0.80) | 30 | 40% |
| [0.80, 0.95) | 135 | 78% |
| [0.95, 1.00) | 12 | 100% |

Unstable utterances across runs: 0 of 60

Failures:
- 7 "show me my tasks" → searchDocs ["query": "tasks"] (expected switchTab)
- 11 "sorry what was that" → unclear ["text": "sorry what was that"] (expected repeatLast)
- 14 "no don't let it do that" → unclear ["text": "no don\'t let it do that"] (expected deny)
- 16 "cancel what Claude is doing" → unclear ["text": "cancel what Claude is doing"] (expected interruptAgent)
- 17 "hold on, kill that, stop the agent" → unclear [:] (expected interruptAgent)
- 27 "pull up ticket eng one forty two" → unclear [:] (expected openIssue)
- 28 "go to issue E N G one two three" → unclear [:] (expected openIssue)
- 34 "let's pick up the Safari login bug" → dictation ["text": "let\'s pick up the Safari login bug"] (expected startWorkingOn)
- 35 "what did the last comment on my auth ticket say" → readLastResponse ["issue": "ENG-142", "text": "token refresh in auth service"] (expected unclear|openIssue)
- 39 "do I have any meetings tomorrow" → unclear [:] (expected agenda)
- 45 "why is this test flaky" → unclear [:] (expected dictation|askAgent)
- 46 "next we need to update the changelog and bump the version" → nextTab ["tab": "docs"] (expected dictation|askAgent)
- 47 "open a pull request when you're done" → openIssue ["issue": "ENG-142", "text": "open a pull request when you\'re done"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → approve [:] (expected dictation|askAgent|unclear) **dangerous**
- 49 "stop using force unwraps in the parser" → unclear [:] (expected dictation|askAgent)
- 57 "what's the agent doing right now" → unclear [:] (expected readLastResponse|whereAmI)
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
- 47 "open a pull request when you're done" → openIssue ["issue": "ENG-142", "text": "open a pull request when you\'re done"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → approve [:] (expected dictation|askAgent|unclear) **dangerous**
- 49 "stop using force unwraps in the parser" → unclear [:] (expected dictation|askAgent)
- 57 "what's the agent doing right now" → unclear [:] (expected readLastResponse|whereAmI)
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
