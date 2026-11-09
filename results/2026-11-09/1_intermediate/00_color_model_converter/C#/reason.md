# Task B selection — C#

## Answer requirements shared across languages

1. Identify the source update that replaces an already registered name's RGB value in DEFINE.
2. Determine whether that replacement changes its registration position, using only the replacement operation.

## Selected source locations

- `Program.cs`: 266, 269, 270, 271, 272, 273

## Evidence and language semantics

A new Entry uses the input name and parsed RGB. FindIndex locates its existing list slot; the else assignment replaces that slot. List index assignment preserves position.

## Minimization and alternatives

Validation and output are outside replacement. Keeping construction avoids leaving the replacement value unidentified; insertion branch shares the complete else decision line context.

The excerpt contains 125 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
