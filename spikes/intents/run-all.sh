#!/bin/zsh
# Runs the P0-05 experiment matrix. Results land in results/*.md|json; console log in results/run-all.log.
set -e
cd "${0:A:h}"
swift build -c release 2>&1 | tail -1
bin=.build/release/intent-spike
$bin check
{
  for schema in a b; do
    for prompt in plain fewshot context; do
      $bin intents --schema $schema --prompt $prompt
    done
  done
  $bin intents --schema ${BEST:-b} --prompt context --prewarm
  $bin intents --schema b --prompt context --stream
  $bin intents --schema ${BEST:-b} --prompt tools
  $bin intents --schema ${BEST:-b} --prompt context --repeat 3 --label ${BEST:-b}-context-repeat3
  $bin summarise
  $bin summarise --permissive
  $bin overflow
} 2>&1 | tee results/run-all.log
