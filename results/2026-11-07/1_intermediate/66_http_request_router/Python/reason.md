# Task B selection — Python

## Answer requirements shared across languages

1. Identify the existing post-refill request-cost comparison and its rejection outcome.
2. Explain how equality is redirected to 429 while preserving the cost scale, refill and existing branch bodies, including any implementation-specific gate dependency.

## Selected source locations

- `main.py`: 257, 259, 636, 637, 638, 652, 657

## Evidence and language semantics

consume returns an integer wait when level < self.period; check_rate passes that wait back; the request handler rejects whenever wait is not None, including zero. Therefore replacing < with <= suffices even though the retained arithmetic returns zero at equality. The request cost remains self.period.

## Minimization and alternatives

The predicate plus return/call chain is necessary because numeric zero and None differ in the 429 gate. A direct branch-only excerpt would not establish this helper dependency. Refill implementation, unrelated counters and routing are unnecessary.

The excerpt contains 163 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
