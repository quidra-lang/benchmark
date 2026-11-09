# Task B selection — C++

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.cpp`: 141, 143

## Evidence and language semantics

term is const string&, and the allDigits arm concatenates term directly to the expression string. A numeric term therefore contributes 0026 as text; no numeric conversion is present in its construction.

## Minimization and alternatives

Keep the term type and its direct concatenation. Other expression arms, parser checks, and final whole-expression return are unnecessary for the requested value construction.

The excerpt contains 49 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
