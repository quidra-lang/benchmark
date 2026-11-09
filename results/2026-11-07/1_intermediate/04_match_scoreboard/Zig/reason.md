# Task B selection — Zig

## Answer requirements shared across languages

1. Explain per-event acceptance of a multi-event POINT, ROLL or THROW and the retained successful prefix when a later event fails.
2. Identify exactly the last successful event removed by a subsequent UNDO, including the empty-history failure.
3. Trace restoration of scores, statistics and finished status, including undoing a match-ending event.

## Selected source locations

- `main.zig`: 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 187, 188, 189, 430, 431, 432, 433, 434, 435, 436, 740, 741, 742, 743, 765, 766, 767, 768, 769, 770, 771, 772, 773, 774, 775, 776, 777, 778, 779, 780, 781, 782, 783, 784, 785

## Evidence and language semantics

Events are expanded and processed sequentially. Validation/finished checks precede acceptance of each event; an error exits the current iteration/command without removing the already accepted prefix. UNDO removes one successful event, even when it was in a multi-event command and even when it ended the match. Empty history is rejected. The stored history contains event name/arguments. Undo pops its last record, restores the initial state, then applies the remaining events in order through the same scoring dispatcher. Consequently scores, accumulated statistics, and the done flag are reconstructed together; replay no longer includes the match-winning event. State.init returns a new value initialized from field defaults and configuration. try propagates rejection before history.append; defaults zero all score/statistical arrays and finished=false. Source bytes and each selected original line were verified against the current develop checkout before inheritance; the excerpt was then independently reviewed. Additional selected error helpers establish actual nonlocal failure; selected scalar/array/frame declarations establish restoration semantics where needed.

## Minimization and alternatives

The full enclosing source interval was considered, but unrelated commands, output formatting outside the requested fields, and unaffected calculations add no required fact. The selected complete lines retain the relevant control decisions and state handoffs. The enclosing interval would cost 12531 tokens; the selected excerpt is smaller. A mere dispatch or assignment line would be insufficient: the retained validation, state and caller evidence is needed to establish the answer. Each requirement was checked against the excerpt alone, using the stated correctness assumption and language semantics.

The excerpt contains 1844 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
