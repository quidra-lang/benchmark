# Task B selection — TypeScript

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `main.ts`: 75, 391, 394, 395

## Evidence and language semantics

registered is a standard Map<string,Color>. set replaces the existing key's value without changing its insertion order, using JavaScript Map semantics.

## Minimization and alternatives

The declaration identifies the receiver library contract. Validation, formatting and sorting are not needed.

The excerpt contains 62 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
