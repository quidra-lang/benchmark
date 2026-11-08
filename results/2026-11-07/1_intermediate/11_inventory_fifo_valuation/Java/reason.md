# Task B selection — Java

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `Main.java`: 7, 100, 101, 102, 103, 282, 283, 284, 285, 529

## Evidence and language semantics

order checks n outside 1..orders.size() through a helper that throws Fault. CANCEL checks o.backorder==0 before cancellation increment. Catch emits ERROR plus unknown order or no backorder; neither exceptional path reaches the increment.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 217 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
