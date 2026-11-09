# Task B selection — JavaScript

## Answer requirements shared across languages

1. Identify the exact unblocked-wait total and count and the existing truncated hundredths conversion.
2. Explain a local half-up conversion with 1/8 becoming 0.13, preserving individual waits, totals, empty summaries and two-digit output.

## Selected source locations

- `main.js`: 443, 444, 445, 446, 447, 448, 449, 450

## Evidence and language semantics

Filter and reduce provide the exact total and count. Math.floor produces truncated hundredths; the ternary protects the empty summary. For nonnegative exact total T and positive count N, compute integer hundredths H=floor((200*T+N)/(2*N)); equivalently divide 100*T by N then increment the quotient when twice its remainder is at least N. This gives H=13 for 1/8. Change only the waits-summary conversion; retain total T, each duration, and quotient/remainder display. In Python and J, use a waits-specific conversion rather than changing a shared truncation helper used by other summaries. Standard sum/filter/count, integer division, remainder, and padding semantics suffice.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 215 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
