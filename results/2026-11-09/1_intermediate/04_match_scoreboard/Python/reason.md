# Task B selection — Python

## Answer requirements shared across languages

1. Explain per-event acceptance of a multi-event POINT, ROLL or THROW and the retained successful prefix when a later event fails.
2. Identify exactly the last successful event removed by a subsequent UNDO, including the empty-history failure.
3. Trace restoration of scores, statistics and finished status, including undoing a match-ending event.

## Selected source locations

- `main.py`: 101, 102, 103, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 120, 121, 122, 123, 124, 125, 126, 127, 138, 139, 140, 141, 142, 143, 144, 298, 299, 300, 301, 387, 388, 389, 416, 417, 418, 419, 420, 421, 422, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 462, 463, 464, 465, 466, 467, 468, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684

## Evidence and language semantics

Events are expanded and processed sequentially. Validation/finished checks precede acceptance of each event; an error exits the current iteration/command without removing the already accepted prefix. UNDO removes one successful event, even when it was in a multi-event command and even when it ended the match. Empty history is rejected. The stored history contains event name/arguments. Undo pops its last record, restores the initial state, then applies the remaining events in order through the same scoring dispatcher. Consequently scores, accumulated statistics, and the done flag are reconstructed together; replay no longer includes the match-winning event. Python deepcopy creates independent nested state; ordinary exception propagation skips history.append for a rejected event. Source bytes and each selected original line were verified against the current develop checkout before inheritance; the excerpt was then independently reviewed. Additional selected error helpers establish actual nonlocal failure; selected scalar/array/frame declarations establish restoration semantics where needed.

## Minimization and alternatives

The full enclosing source interval was considered, but unrelated commands, output formatting outside the requested fields, and unaffected calculations add no required fact. The selected complete lines retain the relevant control decisions and state handoffs. The enclosing interval would cost 9068 tokens; the selected excerpt is smaller. A mere dispatch or assignment line would be insufficient: the retained validation, state and caller evidence is needed to establish the answer. Each requirement was checked against the excerpt alone, using the stated correctness assumption and language semantics.

The excerpt contains 1171 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
