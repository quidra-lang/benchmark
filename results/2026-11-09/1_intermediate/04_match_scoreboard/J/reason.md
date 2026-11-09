# Task B selection — J

## Answer requirements shared across languages

1. Explain per-event acceptance of a multi-event POINT, ROLL or THROW and the retained successful prefix when a later event fails.
2. Identify exactly the last successful event removed by a subsequent UNDO, including the empty-history failure.
3. Trace restoration of scores, statistics and finished status, including undoing a match-ending event.

## Selected source locations

- `main.ijs`: 8, 9, 10, 14, 15, 16, 20, 21, 22, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 115, 116, 129, 130, 131, 190, 191, 192, 193, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 494, 495, 496, 497, 498, 499, 500, 501, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 634, 635, 636, 637, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647

## Evidence and language semantics

Events are expanded and processed sequentially. Validation/finished checks precede acceptance of each event; an error exits the current iteration/command without removing the already accepted prefix. UNDO removes one successful event, even when it was in a multi-event command and even when it ended the match. Empty history is rejected. put records old cell values in D before replacing V. An accepted event links (<D),<HEAD. UNDO walks the last delta in reverse pairs, restores V, follows the previous HEAD and stores the match. The loop breaks on an error but store_match still persists the accepted prefix. The same state vector includes score/statistic/finished cells; restoring it reopens a match ended by the removed event. J amend and boxed-list value semantics preserve the saved old values. Source bytes and each selected original line were verified against the current develop checkout before inheritance; the excerpt was then independently reviewed. Additional selected error helpers establish actual nonlocal failure; selected scalar/array/frame declarations establish restoration semantics where needed.

## Minimization and alternatives

The full enclosing source interval was considered, but unrelated commands, output formatting outside the requested fields, and unaffected calculations add no required fact. The selected complete lines retain the relevant control decisions and state handoffs. The enclosing interval would cost 8437 tokens; the selected excerpt is smaller. A mere dispatch or assignment line would be insufficient: the retained validation, state and caller evidence is needed to establish the answer. Each requirement was checked against the excerpt alone, using the stated correctness assumption and language semantics.

The excerpt contains 913 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
