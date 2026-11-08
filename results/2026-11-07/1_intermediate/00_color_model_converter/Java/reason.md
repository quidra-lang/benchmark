# Task B selection — Java

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `Main.java`: 292, 295, 296, 297, 298, 299, 300

## Evidence and language semantics

The parsed RGB and same name build Entry; the matching list index receives registered.set(i,entry) and returns. List.set replaces an element without insertion or movement.

## Minimization and alternatives

The early return excludes registered.add. No need for the new-name path, color parser internals, or result text.

The excerpt contains 159 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
