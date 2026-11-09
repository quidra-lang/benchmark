# Task B selection — Quidra

## Answer requirements shared across languages

1. Identify the existing post-refill request-cost comparison and its rejection outcome.
2. Explain how equality is redirected to 429 while preserving the cost scale, refill and existing branch bodies, including any implementation-specific gate dependency.

## Selected source locations

- `main.qui`: 571, 573, 574, 575, 576, 577, 578, 579, 580, 581, 582, 583, 584

## Evidence and language semantics

The capped refill precedes clients[id].level < period. That branch computes wait, but the separate wait > 0 guard decides the 429 return. Equality computes zero, so using <= at the bucket comparison alone still reaches success. Coordinate a rejected-zero-wait indicator/gate with the revised threshold while retaining period scale, refill and branch bodies; a literal single-decision change cannot express the full proposal here.

## Minimization and alternatives

The initialized zero wait, comparison, arithmetic and downstream gate are all needed to explain the equality case. A lone comparison would conceal the control dependency; full request processing adds no relevant evidence.

The excerpt contains 250 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
