# Task B selection — Python

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.py`: 147, 150, 151

## Evidence and language semantics

str.split yields string term values; after isdigit succeeds the branch appends term unchanged. The term result is the string 0026, not a parsed integer.

## Minimization and alternatives

Keep the binding, classification and insertion. Other arms and later joining do not alter this value; choosing only parts.append(term) would lose numeric-arm identification.

The excerpt contains 39 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
