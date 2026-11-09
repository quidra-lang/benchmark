# Task B selection — Java

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `Main.java`: 54, 55, 57

## Evidence and language semantics

The loop declares String term, the first-character local feeds the digit arm, and result.append(term) appends the original String. The value remains text 0026.

## Minimization and alternatives

StringBuilder.append(String) supplies the known copying semantics. The three lines connect the selected condition to the string token; unrelated arms and whole-expression assembly are excluded.

The excerpt contains 69 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
