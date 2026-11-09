# Task B selection — Go

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.go`: 184, 185, 186, 187, 188, 189, 457, 458, 459, 460, 461, 462, 463, 464, 465, 966

## Evidence and language semantics

order returns unknown-order error for number outside 1..len(Orders). CANCEL immediately propagates that error, or returns no-backorder error when Backorder==0. The cancelled increment follows both returns; the caller emits ERROR.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 230 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
