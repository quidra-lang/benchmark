# Task B selection — C

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.c`: 232, 233, 234, 235, 236, 237, 238, 506, 507, 508, 509, 510, 511, 512, 513

## Evidence and language semantics

require_order rejects numbers below 1 or above order_count with ERROR unknown order and NULL; CANCEL returns on NULL. A zero backorder prints ERROR no backorder and returns. The cancelled increment is after both early returns.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 203 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
