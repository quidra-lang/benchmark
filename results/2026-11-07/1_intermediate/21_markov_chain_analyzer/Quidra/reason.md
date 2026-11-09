# Task B selection — Quidra

## Answer requirements shared across languages

1. Identify the P command assignment of v to the transition entry indexed by x and y.
2. Explain that other row entries are retained rather than normalized or cleared, and locate subsequent summation of the updated row.

## Selected source locations

- `main.qui`: 59, 60, 61, 62, 63, 397, 398, 399, 400, 401, 402, 403

## Evidence and language semantics

P changes chain.transitions[source][target], stores the changed chain, then ordered_sum reads the same source row through a const array parameter. The selected update targets one indexed cell; it does not replace the row or loop over its other entries. The following rowsum expression reads the same row after the assignment. The selected summation evidence shows addition of those retained entries, so P need not make the row sum one.

## Minimization and alternatives

Keep the P arm, index/value bindings, single-cell write, and updated-row sum. Summation wrappers are traced only to their row selection/addition. ROW replacement, stochastic checks, fraction text formatting and unrelated commands are excluded. A whole-command implementation would add validation unrelated to this local mutation; an assignment alone would omit the required row-sum evidence.

The excerpt contains 201 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
