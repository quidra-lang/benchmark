# Task B selection — Go

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.go`: 79, 81

## Evidence and language semantics

strings.Split yields string term values; the digit arm calls WriteString(term), retaining the exact four characters 0026.

## Minimization and alternatives

The selected loop and numeric arm establish both representation and construction. Depth checks, macro lookup and final whole-expression return are unrelated.

The excerpt contains 54 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
