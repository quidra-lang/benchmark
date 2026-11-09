# Task B selection — Zig

## Answer requirements shared across languages

1. Locate the construction that yields the value of a valid numeric field-expression term spelled 0026.
2. Determine from the construction and source value whether leading-zero text is retained or numeric conversion occurs.

## Selected source locations

- `main.zig`: 94, 95, 416, 417, 420, 421

## Evidence and language semantics

std.mem.splitSequence over u8 produces the term byte slice; the digit branch passes it unchanged to Text.add. The selected add implementation appends the entire slice using the standard appendSlice operation, preserving 0026.

## Minimization and alternatives

The custom Text.add implementation is needed to establish faithful copying. Allocator details, other term arms and the completed-expression return do not affect this term construction.

The excerpt contains 130 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
