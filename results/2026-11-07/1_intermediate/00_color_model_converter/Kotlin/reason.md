# Task B selection — Kotlin

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.kt`: 231, 234, 235, 236, 237

## Evidence and language semantics

Entry contains the parsed RGB under the same name. indexOfFirst chooses the existing list index and indexed assignment replaces it; this preserves list position.

## Minimization and alternatives

The single complete conditional line includes insertion but requires no extra insertion path. Validation and string output are irrelevant.

The excerpt contains 112 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
