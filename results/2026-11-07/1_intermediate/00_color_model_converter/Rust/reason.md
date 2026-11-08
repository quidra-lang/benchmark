# Task B selection — Rust

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.rs`: 496, 498, 499

## Evidence and language semantics

iter_mut().find obtains the existing registry entry by name and its color field alone is assigned. Mutating that field cannot reorder the vector.

## Minimization and alternatives

The successful-match premise excludes else/push. Output and LIST sorting are unrelated, and mutation through the element reference is sufficient without vector implementation.

The excerpt contains 69 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
