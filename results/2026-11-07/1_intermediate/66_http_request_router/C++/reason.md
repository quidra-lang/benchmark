# Task B selection — C++

## Answer requirements shared across languages

1. Identify the existing post-refill request-cost comparison and its rejection outcome.
2. Explain how equality is redirected to 429 while preserving the cost scale, refill and existing branch bodies, including any implementation-specific gate dependency.

## Selected source locations

- `main.cpp`: 593, 596

## Evidence and language semantics

The strict client.level < seconds decision leads to the 429 response. Replace < with <= here. seconds remains the request cost; refill and branch bodies remain.

## Minimization and alternatives

The selected decision and its observable branch establish the requested change. Surrounding request parsing, route dispatch, unrelated response handling and complete routine bodies add no necessary fact. A decision alone would omit its connection to the observed outcome; the full routine is a larger alternative.

The excerpt contains 70 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
