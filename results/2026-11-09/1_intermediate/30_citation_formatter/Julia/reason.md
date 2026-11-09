# Task B selection — Julia

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.jl`: 62, 65, 66

## Evidence and language semantics

split yields text terms; the all_digits branch prints term itself to the expression buffer. print on this string writes 0026 verbatim rather than producing a numeric value.

## Minimization and alternatives

The selected split loop and arm identify the text value and construction. Buffer allocation and whole-expression return are not needed to explain the term result.

The excerpt contains 41 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
