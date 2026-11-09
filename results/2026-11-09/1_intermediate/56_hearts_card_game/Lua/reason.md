# Task B selection — Lua

## Answer requirements shared across languages

1. Identify the SUB-only update and its shooter-seat target.
2. Explain changing that award from -26 to -25 while retaining the earlier 26-point removal and any JD component.

## Selected source locations

- `main.lua`: 669, 688, 689

## Evidence and language semantics

The logical zero-based shooter seat is stored at the one-based array entry points[shooter+1]. Keep the first removal; change the SUB-only decrement. The operation is an incremental subtraction from the existing hand-score entry, so changing its SUB-only decrement to25 preserves the prior value, including any JD contribution. The preceding decrement26 removes penalty points and must remain26; other seats and ADD/AUTO selection are unaffected. Only these adjacent score updates and their branch/target evidence are necessary; card parsing, full scoring implementations, and game-wide totals cannot change which literal must be edited.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 69 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
