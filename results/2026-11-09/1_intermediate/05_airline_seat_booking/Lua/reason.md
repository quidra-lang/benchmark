# Task B selection — Lua

## Answer requirements shared across languages

1. Identify the existing command-name selection for BOOK.
2. Explain a local extension admitting RESERVE to that same path with identical arguments and no new helper.

## Selected source locations

- `main.lua`: 250

## Evidence and language semantics

OR the command test with RESERVE in this elseif. The selection changes only command recognition, leaving the existing block or call and argument values intact.

## Minimization and alternatives

Only the selection site is needed for this explicitly local change. BOOK internals, other command arms, parsers and validation do not need modification. Where a helper is invoked its call identifies the shared target; no helper implementation is needed.

The excerpt contains 13 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
