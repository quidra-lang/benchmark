# Task B selection — Dart

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.dart`: 323, 326, 327

## Evidence and language semantics

String.split produces string terms and the digit arm writes the original term. StringBuffer.write with a string preserves 0026 rather than parsing it as a number.

## Minimization and alternatives

The split/loop establishes the input value type; the selected arm supplies construction. Builder setup, other arms and final joined-expression return are not needed.

The excerpt contains 59 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
