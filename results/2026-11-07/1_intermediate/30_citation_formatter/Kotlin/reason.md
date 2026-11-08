# Task B selection — Kotlin

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.kt`: 55, 57

## Evidence and language semantics

String.split yields String term and its digit arm passes term directly to the StringBuilder receiver. The result contribution is text 0026.

## Minimization and alternatives

The loop and matching arm carry the complete value evidence; other arms, buildString setup and later consumers would repeat it.

The excerpt contains 43 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
