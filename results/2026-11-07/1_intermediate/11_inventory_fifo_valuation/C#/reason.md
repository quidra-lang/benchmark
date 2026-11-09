# Task B selection — C#

## Answer requirements shared across languages

1. Locate CANCEL's unknown-order and zero-backorder tests and state the emitted errors.
2. Determine whether either error path updates cancellation totals.

## Selected source locations

- `Program.cs`: 9, 102, 103, 104, 105, 287, 288, 289, 290, 536

## Evidence and language semantics

order checks n outside 1..orders.Count and error throws Fault. CANCEL next checks backorder==0. Catch prefixes ERROR; the respective messages are unknown order and no backorder. Both throws precede cancelled+=backorder.

## Minimization and alternatives

The excerpt retains both guards, lookup/propagation semantics, the error-message boundary, and the first cancellation update to demonstrate that it is bypassed. Success output, backorder clearing, order creation and unrelated stock totals are unnecessary. Custom fail/error bodies are retained where their names alone do not guarantee an exit; direct throw/return needs no extra implementation.

The excerpt contains 213 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
