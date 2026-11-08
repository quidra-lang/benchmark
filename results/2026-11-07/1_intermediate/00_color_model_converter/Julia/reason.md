# Task B selection — Julia

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.jl`: 275, 276, 278, 279, 280, 281

## Evidence and language semantics

Only a missing key is pushed to registration_order. An existing name skips that block and registered[name] receives a copy of color; its saved order position is untouched.

## Minimization and alternatives

Both the order guard and assignment are necessary because dictionary update alone would not explain the separate order vector. Output and unregister are omitted.

The excerpt contains 64 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
