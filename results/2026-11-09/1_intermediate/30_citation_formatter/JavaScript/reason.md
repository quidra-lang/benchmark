# Task B selection — JavaScript

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.js`: 100, 102

## Evidence and language semantics

String.split yields string map elements and the numeric regular-expression arm returns term directly. The map value is the string 0026, with leading zeros retained.

## Minimization and alternatives

The return construction and split callback suffice. The later join combines terms but cannot change this term value, and other parsing branches add no required fact.

The excerpt contains 47 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
