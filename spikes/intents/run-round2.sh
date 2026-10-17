#!/bin/zsh
# Round 2 (after tuning on ids 1-60): baseline vs v2 on all 83 utterances incl. the hold-out set.
set -e
cd "${0:A:h}"
swift build -c release 2>&1 | tail -1
bin=.build/release/intent-spike
{
  $bin intents --schema b --prompt context --label r2-b-context
  $bin intents --schema b --prompt context --normalise --label r2-b-context-norm
  $bin intents --schema b --prompt v2 --normalise --label r2-b-v2-norm
  $bin intents --schema c --prompt v2 --normalise --label r2-c-v2-norm
  $bin intents --schema c --prompt v2 --normalise --prewarm --label r2-c-v2-norm-prewarm
  $bin summarise --v2
} 2>&1 | tee results/run-round2.log
