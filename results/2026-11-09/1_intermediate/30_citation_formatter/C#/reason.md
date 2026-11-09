# Task B selection — C#

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `Program.cs`: 347, 350

## Evidence and language semantics

The loop explicitly declares term as string and the numeric arm appends that string directly. StringBuilder.Append(string) preserves the four characters 0026, including both leading zeros.

## Minimization and alternatives

The declaration and construction suffice; returning the completed whole expression and other arms add no fact about this term. The explicit string loop is shorter evidence than adding unrelated builder setup and the function return.

The excerpt contains 55 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
