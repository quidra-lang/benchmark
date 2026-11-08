# Task B selection — PHP

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.php`: 92, 93, 94, 95, 96, 97, 379, 380, 381, 382, 383, 384, 837

## Evidence and language semantics

The order range check throws unknown order. The zero-backorder test in CANCEL throws no backorder. Catch emits ERROR plus the exception message; cancellation increment follows the throws and is not executed.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 230 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
