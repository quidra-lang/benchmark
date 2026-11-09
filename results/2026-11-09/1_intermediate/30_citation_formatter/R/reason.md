# Task B selection — R

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.R`: 28, 45, 46, 48

## Evidence and language semantics

split_fixed delegates to character-valued strsplit. The callback receives the resulting term and returns term directly when all_digits holds. Thus 0026 is retained as character text.

## Minimization and alternatives

The one-line split wrapper is included because it is custom. Its call and callback return are sufficient; vapply collection type and whole-expression concatenation are unnecessary for the value of the term itself.

The excerpt contains 86 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
