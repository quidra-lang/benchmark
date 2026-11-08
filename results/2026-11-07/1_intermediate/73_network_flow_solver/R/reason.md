# Task B selection — R

## Answer requirements shared across languages

1. Identify DECOMPOSE working-flow initialization from stored edge-flow values.
2. Determine independence or aliasing from language/container semantics and cite one subsequent working-flow subtraction to establish whether stored edge flow can change.

## Selected source locations

- `main.R`: 178, 196

## Evidence and language semantics

Selecting the named flow column yields a numeric vector. R vectors use value semantics on modification; replacing remaining[cycle] changes the working vector, not network$edges.

## Minimization and alternatives

The initialization plus one real subtraction is sufficient. The full decomposition algorithm, path search, bottleneck calculation and output add no aliasing evidence. Where necessary the fresh allocation/value container or helper argument connection is retained; a binding alone would omit the requested write evidence.

The excerpt contains 34 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
