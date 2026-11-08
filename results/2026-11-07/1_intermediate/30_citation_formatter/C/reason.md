# Task B selection — C

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.c`: 36, 38, 39, 41, 295, 297

## Evidence and language semantics

The numeric-term arm passes the char-pointer term unchanged to append; append delegates its full strlen to append_n, whose memcpy preserves the bytes. Thus the result contains text 0026, not integer 26. The selected copy operation supplies the custom Text semantics.

## Minimization and alternatives

The branch and char-pointer declaration are needed to identify the original token and its destination. Selecting only the append call would hide custom copying semantics. Allocator growth, other term arms, and bibliography formatting do not affect this expression.

The excerpt contains 161 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
