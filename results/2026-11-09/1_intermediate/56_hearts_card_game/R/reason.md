# Task B selection — R

## Answer requirements shared across languages

1. Identify the SUB-only update and its shooter-seat target.
2. Explain changing that award from -26 to -25 while retaining the earlier 26-point removal and any JD component.

## Selected source locations

- `main.R`: 275, 281

## Evidence and language semantics

values[shooter] is the shooter entry. Preserve the first removal; replace only the SUB expression minus26L with minus25L in the complete conditional line. The operation is an incremental subtraction from the existing hand-score entry, so changing its SUB-only decrement to25 preserves the prior value, including any JD contribution. The preceding decrement26 removes penalty points and must remain26; other seats and ADD/AUTO selection are unaffected. Only these adjacent score updates and their branch/target evidence are necessary; card parsing, full scoring implementations, and game-wide totals cannot change which literal must be edited.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 74 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
