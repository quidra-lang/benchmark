# Task B selection — Python

## Answer requirements shared across languages

1. Identify DECOMPOSE working-flow initialization from stored edge-flow values.
2. Determine independence or aliasing from language/container semantics and cite one subsequent working-flow subtraction to establish whether stored edge flow can change.

## Selected source locations

- `main.py`: 24, 126, 141, 154, 164

## Evidence and language semantics

Edge.flow is initialized to integer zero; the list comprehension copies those numeric values into a new list. trace_piece receives that list and performs the shown subtraction in its remaining parameter. Integer values are immutable, so replacing a working-list slot cannot alter the original edge.flow.

## Minimization and alternatives

The initialization plus one real subtraction is sufficient. The full decomposition algorithm, path search, bottleneck calculation and output add no aliasing evidence. Where necessary the fresh allocation/value container or helper argument connection is retained; a binding alone would omit the requested write evidence.

The excerpt contains 75 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
