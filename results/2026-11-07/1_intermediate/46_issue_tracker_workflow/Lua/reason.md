# Task B selection — Lua

## Answer requirements shared across languages

1. Trace a successful ASSIGN mutation and the event content supplied to history recording.
2. Show how recording captures the current day and assignee text into stored data and how HISTORY later emits that entry.
3. Use ownership/value semantics to explain why later ASSIGN or DAY cannot alter the earlier recorded event.

## Selected source locations

- `main.lua`: 168, 169, 210, 215, 222, 625, 626, 627, 628

## Evidence and language semantics

ASSIGN updates issue.assignee and supplies command plus args[2]. Concatenation immediately constructs an immutable Lua string containing self.day and text; history stores that scalar string and HISTORY emits it. The captured history text is day D ASSIGN U (using the successful command's assignee spelling, including the unassigned marker when applicable). Recording does not store a deferred getter, closure or pointer to a mutable day/assignee field. Updating those fields later therefore cannot retroactively recompute the existing entry.

## Minimization and alternatives

A successful assignment is the scenario premise, so unrelated validation branches are not needed. Selected lines retain the actual mutation, supplied event values, eager text construction/storage and HISTORY reader. Generic issue creation, DAY dispatch and other event kinds add no ownership fact. In languages with immutable strings or value semantics, no extra copy implementation is required; C and Zig retain the actual independent byte-allocation evidence.

The excerpt contains 179 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
