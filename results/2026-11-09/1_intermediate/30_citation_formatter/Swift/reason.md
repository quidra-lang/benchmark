# Task B selection — Swift

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.swift`: 165, 168, 169

## Evidence and language semantics

components(separatedBy:) yields String terms; the allDigits arm concatenates term directly. The result contribution is 0026 as a String, with both leading zeros.

## Minimization and alternatives

The source binding and construction suffice. Buffer setup, other arms and final return do not change this term value.

The excerpt contains 49 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
