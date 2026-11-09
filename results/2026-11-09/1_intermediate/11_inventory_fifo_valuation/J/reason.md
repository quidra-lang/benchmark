# Task B selection — J

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.ijs`: 48, 49, 257, 258, 259, 260, 264, 265, 266, 267, 286

## Evidence and language semantics

Order index is parsed minus one and checked against 0..NO-1; invalid IDs print ERROR unknown order and return. In CANCEL the backorder slot (6) equal to zero prints ERROR no backorder and returns before the cancellation slot (7) update. The output field mapping identifies those slots.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 224 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
