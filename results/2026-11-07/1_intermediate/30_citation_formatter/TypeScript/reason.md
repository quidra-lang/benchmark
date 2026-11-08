# Task B selection — TypeScript

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.ts`: 155, 157

## Evidence and language semantics

String.split yields string callback elements, and the numeric regular-expression arm returns term directly. Its value is string 0026, not numeric 26.

## Minimization and alternatives

The callback binding and direct return contain all term-value evidence. The subsequent join and macro arms are unnecessary.

The excerpt contains 47 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
