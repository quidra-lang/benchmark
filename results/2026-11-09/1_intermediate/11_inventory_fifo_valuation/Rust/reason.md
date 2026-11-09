# Task B selection — Rust

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `main.rs`: 166, 167, 168, 169, 170, 171, 172, 457, 458, 459, 460, 461, 462, 463, 930

## Evidence and language semantics

order_index returns Err unknown order when ID is outside the stored range. CANCEL's ? propagates it; zero backorder explicitly returns Err no backorder. ERROR output is selected and the cancelled increment comes after both exits.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 265 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
