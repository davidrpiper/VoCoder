### r2-c-v2-norm

schema=c prompt=v2 prewarm=false stream=false permissive=false normalise=true runs=1 n=83 instructionTokens=1215

| Metric | Value |
|---|---|
| Kind accuracy | 76% |
| Kind + slots | 76% |
| Dangerous errors (risky kind chosen wrongly) | 1 |
| Errors thrown | 3 |
| First call (incl. load) | 2690 ms |
| Latency p50 / p95 / max (rest) | 6101 / 9588 / 11610 ms |

| Set | n | kind | kind+slots | wrong action (not unclear) | dangerous |
|---|---|---|---|---|---|
| tuning 1–60 | 60 | 80% | 80% | 8 | 1 |
| hold-out 61+ | 23 | 65% | 65% | 4 | 0 |
| all | 83 | 76% | 76% | 12 | 1 |

| Category | n | kind | kind+slots |
|---|---|---|---|
| ambiguous | 7 | 86% | 86% |
| clean | 20 | 95% | 95% |
| dictation | 5 | 80% | 80% |
| dictation-trap | 4 | 25% | 25% |
| holdout-ambiguous | 2 | 100% | 100% |
| holdout-clean | 6 | 83% | 83% |
| holdout-dictation | 3 | 67% | 67% |
| holdout-loose | 11 | 55% | 55% |
| holdout-spoken-form | 1 | 0% | 0% |
| loose | 21 | 81% | 81% |
| out-of-schema | 1 | 0% | 0% |
| spoken-form | 2 | 50% | 50% |

| Confidence | n | kind correct |
|---|---|---|
| [0.00, 0.50) | 0 | - |
| [0.50, 0.80) | 0 | - |
| [0.80, 0.95) | 0 | - |
| [0.95, 1.00) | 0 | - |

Failures:
- 3 "switch to the API" → guardrailViolation (expected switchTab)
- 7 "show me my tasks" → whereAmI ["tab": "api", "issue": "ENG-142"] (expected switchTab)
- 14 "no don't let it do that" → unclear ["issue": "ENG-142", "text": "no don\'t let it do that", "tab": "api"] (expected deny)
- 25 "diff of the readme" → guardrailViolation (expected showDiff)
- 27 "pull up ticket eng one forty two" → searchDocs ["query": "ticket ENG-142"] (expected openIssue)
- 35 "what did the last comment on my auth ticket say" → readLastResponse ["issue": "ENG-142", "text": "The last comment on my auth ticket said: \'Fix token refresh in auth service.\'"] (expected unclear|openIssue)
- 45 "why is this test flaky" → unclear ["text": "why is this test flaky"] (expected dictation|askAgent)
- 46 "next we need to update the changelog and bump the version" → switchTab ["tab": "docs"] (expected dictation|askAgent)
- 47 "open a pull request when you're done" → openIssue ["text": "open a pull request when you\'re done", "issue": "ENG-142"] (expected dictation|askAgent)
- 48 "approve the PR once CI passes" → approve ["text": "approve the PR once CI passes"] (expected dictation|askAgent|unclear) **dangerous**
- 52 "the other one" → switchTab ["tab": "web-app"] (expected unclear)
- 57 "what's the agent doing right now" → askAgent ["text": "what\'s the agent doing right now"] (expected readLastResponse|whereAmI)
- 61 "flip to the calendar" → unclear [:] (expected switchTab)
- 62 "go one tab to the right" → switchTab ["tab": "web-app"] (expected nextTab)
- 65 "nope, block that command" → unclear ["tab": "api", "issue": "ENG-142", "text": "block that command"] (expected deny)
- 66 "abort, abort" → guardrailViolation (expected interruptAgent|unclear)
- 69 "let me see the changes in token tests" → whatChanged ["text": "Sources/Auth/AuthService.swift, Tests/AuthTests/TokenTests.swift, README.md", "issue": "ENG-142", "tab": "api"] (expected showDiff)
- 70 "bring up ENG-98" → searchDocs ["query": "Deploy pipeline flakes on staging"] (expected openIssue)
- 77 "stop the build from caching node modules" → unclear ["issue": "ENG-142", "text": "stop the build from caching node modules", "tab": "api"] (expected dictation|askAgent)
- 83 "pull up ticket eng ninety eight" → searchDocs ["query": "deploys"] (expected openIssue)
