# Task B selection — Lua

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.lua`: 52, 53, 91, 92, 93, 94, 95, 96, 351, 352, 353, 354, 739

## Evidence and language semantics

order converts and checks number in 1..#orders. fail calls Lua error with the reason. CANCEL checks zero backorder and fails before the cancelled assignment. The error catch emits ERROR and the stored reason.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 196 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
