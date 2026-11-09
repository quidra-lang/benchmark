# Task B selection — JavaScript

## Answer requirements shared across languages

1. Explain per-event acceptance of a multi-event POINT, ROLL or THROW and the retained successful prefix when a later event fails.
2. Identify exactly the last successful event removed by a subsequent UNDO, including the empty-history failure.
3. Trace restoration of scores, statistics and finished status, including undoing a match-ending event.

## Selected source locations

- `main.js`: 6, 7, 8, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 272, 273, 274, 275, 338, 339, 340, 341, 388, 389, 390, 391, 392, 393, 394, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612, 613

## Evidence and language semantics

Events are expanded and processed sequentially. Validation/finished checks precede acceptance of each event; an error exits the current iteration/command without removing the already accepted prefix. UNDO removes one successful event, even when it was in a multi-event command and even when it ended the match. Empty history is rejected. The stored history contains event name/arguments. Undo pops its last record, restores the initial state, then applies the remaining events in order through the same scoring dispatcher. Consequently scores, accumulated statistics, and the done flag are reconstructed together; replay no longer includes the match-winning event. structuredClone creates an independent initial snapshot. Its initializer includes done, scoring arrays, rally and dart statistics, so reset/replay covers them together. Source bytes and each selected original line were verified against the current develop checkout before inheritance; the excerpt was then independently reviewed. Additional selected error helpers establish actual nonlocal failure; selected scalar/array/frame declarations establish restoration semantics where needed.

## Minimization and alternatives

The full enclosing source interval was considered, but unrelated commands, output formatting outside the requested fields, and unaffected calculations add no required fact. The selected complete lines retain the relevant control decisions and state handoffs. The enclosing interval would cost 8695 tokens; the selected excerpt is smaller. A mere dispatch or assignment line would be insufficient: the retained validation, state and caller evidence is needed to establish the answer. Each requirement was checked against the excerpt alone, using the stated correctness assumption and language semantics.

The excerpt contains 1161 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
