# Task B selection — Ruby

## Answer requirements shared across languages

1. Identify DECOMPOSE working-flow initialization from stored edge-flow values.
2. Determine independence or aliasing from language/container semantics and cite one subsequent working-flow subtraction to establish whether stored edge flow can change.

## Selected source locations

- `main.rb`: 195, 210

## Evidence and language semantics

map(&:flow) creates a fresh array of scalar numeric values. Integers are immutable; the indexed -= stores a new value only in remaining.

## Minimization and alternatives

The initialization plus one real subtraction is sufficient. The full decomposition algorithm, path search, bottleneck calculation and output add no aliasing evidence. Where necessary the fresh allocation/value container or helper argument connection is retained; a binding alone would omit the requested write evidence.

The excerpt contains 42 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
