# Task B selection — R

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.R`: 40, 41, 42, 43, 92, 93, 94, 95, 346, 347, 348, 349, 765

## Evidence and language semantics

lookup_order checks ID below 1 or above length(inv$orders) via fail. CANCEL fails for order$backorder==0. fail signals the selected command_error caught with ERROR; cancelled assignment follows both conditions and is bypassed.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 247 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
