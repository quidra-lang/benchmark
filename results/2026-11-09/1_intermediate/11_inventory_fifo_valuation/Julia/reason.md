# Task B selection — Julia

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.jl`: 28, 129, 130, 131, 132, 343, 344, 345, 346, 703

## Evidence and language semantics

lookup_order accepts 1<=number<=length(inv.orders), otherwise the short-circuit OR calls throwing fail. CANCEL requires backorder>0 using the same throw. The ERROR catch displays unknown order or no backorder, before any cancellation increment.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 182 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
