# Task B selection — Quidra

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.qui`: 141, 144, 145

## Evidence and language semantics

The split loop binds a string term. The all_digits arm concatenates the original term directly to result, retaining text 0026. There is no numeric conversion in this construction.

## Minimization and alternatives

The loop and numeric arm suffice to establish the term representation and contribution. Braces, macros, full expression return and bibliography consumers add no needed evidence.

The excerpt contains 39 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
