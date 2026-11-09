# Task B selection — Julia

## Answer requirements shared across languages

1. Trace a successful ASSIGN mutation and the event content supplied to history recording.
2. Show how recording captures the current day and assignee text into stored data and how HISTORY later emits that entry.
3. Use ownership/value semantics to explain why later ASSIGN or DAY cannot alter the earlier recorded event.

## Selected source locations

- `main.jl`: 105, 446, 447, 463, 471, 477

## Evidence and language semantics

ASSIGN updates target, then passes interpolated cmd/target to record!. That helper constructs the day-prefixed String immediately and pushes it into history. HISTORY returns these stored string entries. The captured history text is day D ASSIGN U (using the successful command's assignee spelling, including the unassigned marker when applicable). Recording does not store a deferred getter, closure or pointer to a mutable day/assignee field. Updating those fields later therefore cannot retroactively recompute the existing entry.

## Minimization and alternatives

A successful assignment is the scenario premise, so unrelated validation branches are not needed. Selected lines retain the actual mutation, supplied event values, eager text construction/storage and HISTORY reader. Generic issue creation, DAY dispatch and other event kinds add no ownership fact. In languages with immutable strings or value semantics, no extra copy implementation is required; C and Zig retain the actual independent byte-allocation evidence.

The excerpt contains 131 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
