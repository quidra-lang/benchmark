# Task B selection — Swift

## Answer requirements shared across languages

1. Explain per-event acceptance of a multi-event POINT, ROLL or THROW and the retained successful prefix when a later event fails.
2. Identify exactly the last successful event removed by a subsequent UNDO, including the empty-history failure.
3. Trace restoration of scores, statistics and finished status, including undoing a match-ending event.

## Selected source locations

- `main.swift`: 3, 4, 5, 6, 7, 8, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 134, 197, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 439, 440, 441, 442, 443, 444, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462

## Evidence and language semantics

Events are expanded and processed sequentially. Validation/finished checks precede acceptance of each event; an error exits the current iteration/command without removing the already accepted prefix. UNDO removes one successful event, even when it was in a multi-event command and even when it ended the match. Empty history is rejected. The saved record contains old values only for changed state-array cells plus the previous completed-set list length. Undo restores those cells and truncates that list. The done/winner cells and statistics occupy the same array, so they are restored with scores rather than updated independently. Swift Array has value semantics: let before = s retains the old numeric array through later mutations; popLast removes one record. throw/try exits the event loop without undoing accepted records. Source bytes and each selected original line were verified against the current develop checkout before inheritance; the excerpt was then independently reviewed. Additional selected error helpers establish actual nonlocal failure; selected scalar/array/frame declarations establish restoration semantics where needed.

## Minimization and alternatives

The full enclosing source interval was considered, but unrelated commands, output formatting outside the requested fields, and unaffected calculations add no required fact. The selected complete lines retain the relevant control decisions and state handoffs. The enclosing interval would cost 8260 tokens; the selected excerpt is smaller. A mere dispatch or assignment line would be insufficient: the retained validation, state and caller evidence is needed to establish the answer. Each requirement was checked against the excerpt alone, using the stated correctness assumption and language semantics.

The excerpt contains 1182 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
