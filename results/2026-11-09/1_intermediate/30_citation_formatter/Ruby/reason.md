# Task B selection — Ruby

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.rb`: 63, 66, 67

## Evidence and language semantics

String#split yields string term values. The digit arm yields term itself from the map block, so 0026 remains the original string.

## Minimization and alternatives

The binding and result arm suffice under Ruby string/map semantics. Joining the expression and processing other arm types are not needed.

The excerpt contains 41 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
