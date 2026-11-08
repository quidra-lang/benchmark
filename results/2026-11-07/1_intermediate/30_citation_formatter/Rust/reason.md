# Task B selection — Rust

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.rs`: 43, 44, 46

## Evidence and language semantics

str::split yields &str term. The byte match chooses the decimal-digit arm and push_str(term) copies the original text 0026 into the result String.

## Minimization and alternatives

The match input is necessary to connect the byte range to the term. Other arms, buffer setup and final Ok(result) add no fact about the numeric term representation.

The excerpt contains 61 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
