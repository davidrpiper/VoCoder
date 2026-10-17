Claude Code 2.1.302 stream-json transcripts, copied from `spikes/claude-code/fixtures` (P0-04;
scrubbed of paths and account data). `<name>.out.ndjson` is the CLI's stdout, `<name>.in.ndjson`
what the spike wrote to its stdin. `ClaudeReplayTests` replays them through `ReplayTransport`.
Re-record with the spike (`cc-spike run …`, then `cc-spike scrub`) when the protocol changes.
