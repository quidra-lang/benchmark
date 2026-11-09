# Task B selection — Quidra

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.qui`: 55, 56, 247, 248, 249, 250, 251, 252, 255, 256, 257, 258, 259

## Evidence and language semantics

The parsed zero-based index outside the stored order count prints ERROR unknown order and returns. For an existing order with backorder==0 fail prints ERROR no backorder; cancellation increment is in the else branch. Neither path changes cancellation totals.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 202 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
