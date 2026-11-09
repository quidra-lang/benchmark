# Task B selection — JavaScript

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.js`: 72, 388, 391, 392

## Evidence and language semantics

registered is a standard Map. set(name,color) updates the existing key's RGB and preserves its original insertion position, as guaranteed by Map.set.

## Minimization and alternatives

Map construction identifies the receiver semantics. Validation and result formatting cannot affect replacement; LIST sorts separately and is outside the question.

The excerpt contains 56 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
