# Task B selection — Zig

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.zig`: 101, 102, 103, 120, 121, 122, 123, 312, 313, 314, 315, 316, 633

## Evidence and language semantics

order returns the custom error on ID outside 1..orders.items.len. try propagates it from CANCEL. Zero backorder returns the no-backorder error. fail stores the formatted reason and returns BadCommand; ERROR printing occurs before any cancellation increment can be reached.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 356 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
