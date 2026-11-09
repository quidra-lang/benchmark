# Task B selection — Dart

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.dart`: 209, 241, 245, 246

## Evidence and language semantics

registered is the insertion-ordered Dart map literal. Assigning the new color under an existing key updates its value without moving the key in map iteration order.

## Minimization and alternatives

The map declaration is needed to use Map semantics instead of guessing an operator implementation. Name validation and output do not affect replacement.

The excerpt contains 63 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
