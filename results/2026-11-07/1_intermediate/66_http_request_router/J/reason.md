# Task B selection — J

## Answer requirements shared across languages

1. Identify the existing post-refill request-cost comparison and its rejection outcome.
2. Explain how equality is redirected to 429 while preserving the cost scale, refill and existing branch bodies, including any implementation-specific gate dependency.

## Selected source locations

- `main.ijs`: 539, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551

## Evidence and language semantics

level is refilled and capped in Capacity*Period units. level<Period selects computation of wait, while wait>0 separately controls the 429 return. Equality makes the existing ceiling expression zero, so changing the first < to <: (less-or-equal) alone is insufficient: the rejection gate must distinguish a rejected zero-wait outcome from success. Preserve Period as cost, refill and response bodies; coordinate that gate/sentinel with the revised threshold. This dependency prevents a literal one-comparison edit from achieving the proposal in this implementation.

## Minimization and alternatives

The refill, strict threshold, zero initialization and later wait gate are necessary to expose the equality path accurately. Selecting only level<Period would falsely imply a sufficient single edit. Generic header/routing code and unrelated counters are excluded.

The excerpt contains 174 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
