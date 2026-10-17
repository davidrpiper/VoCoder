### overflow

contextSize=4096

| Input | Prompt tok | Result | ms |
|---|---|---|---|
| whole session digest ×1 | 2401 | ok: Here's a summary of everything we've done in this session:  1. **Read `README.md | 6293 |
| whole session digest ×2 | 4796 | exceededContextWindowSize | 780 |
| whole session digest ×3 | 7191 | exceededContextWindowSize | 1225 |
