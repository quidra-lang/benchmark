# Task B selection — Lua

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.lua`: 303, 306

## Evidence and language semantics

The numeric-term branch places term itself in the values table. No tonumber operation constructs this value, so the numeric token contributes its original string 0026.

## Minimization and alternatives

The iteration binding and direct table insertion identify the original token and its result. The split helper only locates terms; full field assembly and macro lookup do not affect the construction being asked about.

The excerpt contains 52 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
