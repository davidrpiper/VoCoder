### default-v2

guardrails=default v2=true

| Turn | Request | Prompt tok | ms | Words | On-device summary | Claude `<spoken>` |
|---|---|---|---|---|---|---|
| spoken-sonnet#0 | What does README.md say? Read it. | 79 | 4398 | 20 | The README is very short. It has a title, "Spike repo", and one line saying the project codename is BLUEBIRD. | The README is just two lines. It's titled Spike repo and says the project codename is BLUEBIRD. |
| spoken-sonnet#4 | Create notes.txt containing a haiku about git. | 185 | 2720 | 36 | I created notes.txt in the repo root with this haiku: My first draft had a line with too many syllables, so I rewrote it. The file has the corrected version, and it isn't committed. | I created notes.txt with a git haiku about branches, commits, and detached HEAD. I fixed a syllable count on the second line, and the file isn't committed. |
| spoken-sonnet#5 | Explain in detail the difference between a process and a thr | 659 | 3103 | 38 | A process is a running program with its own isolated resources, while a thread is a unit of execution inside a process that shares most of its resources but has its own stack, registers, and thread-local storage. | A process is a running program with its own isolated memory and resources. A thread is an execution path inside a process that shares its memory. Threads are cheaper but riskier. Processes are safer but costlier to communicate between. |
| spoken-sonnet#6 | Run git log and tell me how many commits there are. | 90 | 524 | 20 | There is 1 commit on the current branch: cfc22b5 init. The notes.txt file I created earlier isn't committed. | There's just one commit, called init. The notes file I made earlier hasn't been committed yet. |
| spoken-sonnet#9 | Give me a markdown table of 3 HTTP status codes and their me | 40 | 1266 | 0 | **decodingFailure** | Here's a table with three status codes: 200 means success, 404 means the resource wasn't found, and 500 means an internal server error. |
| spoken-sonnet#11 | Summarise everything we've done in this session. | 320 | 742 | 23 | We read the README.md, created notes.txt, and ran git log. The only change to the repo is the uncommitted notes.txt. | We read the README, wrote a Swift reverse function, answered a math question, and listed CLI names. We also made a git haiku file, explained processes and threads, and checked the log and tests. Only the notes file is uncommitted. |
| spoken-sonnet#14 | Fix the typo in README.md if there is one. | 63 | 567 | 22 | I found no typo in README.md, so I made no changes. It reads "# Spike repo" and "The project codename is BLUEBIRD." | I found no typos in the README, so I left it unchanged. |
| permission-host#1 | Use the Bash tool to run exactly this command: rm README.md. | 218 | 770 | 30 | The rm README.md command was declined, so README.md is still there. Before the refusal, it was 48 bytes and contained '# Spike repo' and 'The project codename is BLUEBIRD.' | – |
| todos#0 | Use your task tools to create a 3 item list (lint, test, shi | 181 | 3382 | 35 | I created three tasks (lint, test, ship). Lint is now in progress and test is marked completed. Ship is still pending. I stopped there as you asked, and I didn't run any other commands. | – |

Latency p50 / max: 2720 / 4398 ms. Errors: 1.
