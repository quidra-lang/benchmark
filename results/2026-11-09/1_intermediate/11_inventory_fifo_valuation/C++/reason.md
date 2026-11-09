# Task B selection — C++

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.cpp`: 141, 142, 164, 165, 166, 167, 168, 169, 437, 438, 439, 440, 441, 442, 943

## Evidence and language semantics

order validates 1..orders.size(); error throws runtime_error. CANCEL checks current.backorder==0 before incrementing cancelled. Both errors unwind to the ERROR emitter and skip the increment.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 253 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
