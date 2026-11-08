# Task B selection — Julia

## Answer requirements shared across languages

1. Explain per-event acceptance of a multi-event POINT, ROLL or THROW and the retained successful prefix when a later event fails.
2. Identify exactly the last successful event removed by a subsequent UNDO, including the empty-history failure.
3. Trace restoration of scores, statistics and finished status, including undoing a match-ending event.

## Selected source locations

- `main.jl`: 21, 23, 178, 240, 355, 356, 357, 358, 359, 360, 361, 362, 363, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 395, 396, 397, 398, 399, 400, 401, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425

## Evidence and language semantics

Events are expanded and processed sequentially. Validation/finished checks precede acceptance of each event; an error exits the current iteration/command without removing the already accepted prefix. UNDO removes one successful event, even when it was in a multi-event command and even when it ended the match. Empty history is rejected. POINT stores its old score/server/run/completed-list values plus flags describing statistics increments. Undo decrements those exact statistics, restores score/run values, truncates completed units and clears the winner. ROLL/THROW instead retain the old state and restore that entire state. The history therefore records one event, not one input command. deepcopy supplies independent Dict snapshots; pop! removes the final record. POINT uses integer records, so its explicit inverse statistics and winner restoration are necessary evidence. Source bytes and each selected original line were verified against the current develop checkout before inheritance; the excerpt was then independently reviewed. Additional selected error helpers establish actual nonlocal failure; selected scalar/array/frame declarations establish restoration semantics where needed.

## Minimization and alternatives

The full enclosing source interval was considered, but unrelated commands, output formatting outside the requested fields, and unaffected calculations add no required fact. The selected complete lines retain the relevant control decisions and state handoffs. The enclosing interval would cost 3604 tokens; the selected excerpt is smaller. A mere dispatch or assignment line would be insufficient: the retained validation, state and caller evidence is needed to establish the answer. Each requirement was checked against the excerpt alone, using the stated correctness assumption and language semantics.

The excerpt contains 942 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
