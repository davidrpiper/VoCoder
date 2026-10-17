### r2-b-v2-norm

schema=b prompt=v2 prewarm=false stream=false permissive=false normalise=true runs=1 n=83 instructionTokens=1215

| Metric | Value |
|---|---|
| Kind accuracy | 80% |
| Kind + slots | 78% |
| Dangerous errors (risky kind chosen wrongly) | 1 |
| Errors thrown | 0 |
| First call (incl. load) | 1370 ms |
| Latency p50 / p95 / max (rest) | 1464 / 4269 / 6166 ms |

| Set | n | kind | kind+slots | wrong action (not unclear) | dangerous |
|---|---|---|---|---|---|
| tuning 1–60 | 60 | 83% | 82% | 6 | 1 |
| hold-out 61+ | 23 | 70% | 70% | 3 | 0 |
| all | 83 | 80% | 78% | 9 | 1 |

| Category | n | kind | kind+slots |
|---|---|---|---|
| ambiguous | 7 | 100% | 100% |
| clean | 20 | 100% | 95% |
| dictation | 5 | 80% | 80% |
| dictation-trap | 4 | 25% | 25% |
| holdout-ambiguous | 2 | 100% | 100% |
| holdout-clean | 6 | 83% | 83% |
| holdout-dictation | 3 | 67% | 67% |
| holdout-loose | 11 | 64% | 64% |
| holdout-spoken-form | 1 | 0% | 0% |
| loose | 21 | 81% | 81% |
| out-of-schema | 1 | 0% | 0% |
| spoken-form | 2 | 50% | 50% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 1 | 100% |
| [0.50, 0.80) | 14 | 57% |
| [0.80, 0.95) | 63 | 83% |
| [0.95, 1.00) | 5 | 100% |

Failures:
- 7 "show me my tasks" → whereAmI ["tab": "api", "issue": "ENG-142"] (expected switchTab)
- 14 "no don't let it do that" → unclear [:] (expected deny)
- 27 "pull up ticket eng one forty two" → unclear [:] (expected openIssue)
- 35 "what did the last comment on my auth ticket say" → readLastResponse [:] (expected unclear|openIssue)
- 36 "search the docs for onboarding" → searchDocs [:] (expected searchDocs)
- 39 "do I have any meetings tomorrow" → unclear [:] (expected agenda)
- 45 "why is this test flaky" → unclear [:] (expected dictation|askAgent)
- 46 "next we need to update the changelog and bump the version" → switchTab ["tab": "docs"] (expected dictation|askAgent)
- 47 "open a pull request when you're done" → openIssue ["issue": "ENG-142", "text": "open a pull request when you\'re done"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → approve [:] (expected dictation|askAgent|unclear) **dangerous**
- 57 "what's the agent doing right now" → askAgent ["text": "what\'s the agent doing right now"] (expected readLastResponse|whereAmI)
- 61 "flip to the calendar" → unclear [:] (expected switchTab)
- 62 "go one tab to the right" → switchTab ["tab": "web-app"] (expected nextTab)
- 65 "nope, block that command" → unclear ["text": "block that command"] (expected deny)
- 69 "let me see the changes in token tests" → whatChanged ["tab": "api", "issue": "ENG-142"] (expected showDiff)
- 70 "bring up ENG-98" → searchDocs ["query": "deploys"] (expected openIssue)
- 77 "stop the build from caching node modules" → unclear [:] (expected dictation|askAgent)
- 83 "pull up ticket eng ninety eight" → unclear [:] (expected openIssue)
