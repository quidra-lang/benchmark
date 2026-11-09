# Task B selection — PHP

## Answer requirements shared across languages

1. Trace numeric, bar and off PLAY syntax, optional hit marks/path repetition, and Black own-number to board-point correspondence.
2. Explain construction of a temporary proposed position, rule rejection and recognition by equality with generated legal plays.
3. Give a valid Black example and its final canonical notation, identifying success-only mutation and invalid/unmatched exits.

## Selected source locations

- `main.php`: 6, 7, 8, 9, 10, 11, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 572, 647, 648, 649, 650, 669, 670, 671, 672, 673, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688, 689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720, 721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734

## Evidence and language semantics

parsePlay validates paths and expands own-number pairs, using bar25/off0. PHP array value semantics isolate final from state; Black output reflects25-p. ensure throws before applyPlay on all failures. positionKey covers both complete rows, and only a legal exact match reaches the canonical text output and state update. Numeric notation always uses the moving player's own numbering: Black own point p corresponds to board point25-p, with bar/off remaining special sentinels25/0 rather than ordinary reflected board points. For a Black position with the usual starting checkers and dice1,2, PLAY 1 2 6/4 6/5 requests own6->4 and6->5, i.e. board19->21 and19->20; both are legal, non-hitting moves using both dice. Descending source/target canonical order gives OK 6/5 6/4, independent of input token order. A proposed final position is isolated from current state; the returned/generated legal candidate supplies canonical notation and is committed only after all checks. The generator search itself is outside this parsing routine: its legal collection is consumed by exact complete-position comparison, so evaluation, dice search and game/match scoring are unnecessary to explain recognition or failure non-mutation.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 3057 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
