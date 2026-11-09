# Task B selection — Quidra

## Answer requirements shared across languages

1. Trace numeric, bar and off PLAY syntax, optional hit marks/path repetition, and Black own-number to board-point correspondence.
2. Explain construction of a temporary proposed position, rule rejection and recognition by equality with generated legal plays.
3. Give a valid Black example and its final canonical notation, identifying success-only mutation and invalid/unmatched exits.

## Selected source locations

- `main.qui`: 5, 6, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 86, 87, 88, 89, 90, 91, 92, 93, 94, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 152, 462, 586, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650

## Evidence and language semantics

parse_play validates canonical numeric words, bar25/off0 and repetitions. Black board expression reads men[1][25-point]; value semantics isolate final_position. Error returns precede make_play, which is reached only for equal generated legal final_position. canonical_key and notation supply the accepted sorted/merged/grouped text. Numeric notation always uses the moving player's own numbering: Black own point p corresponds to board point25-p, with bar/off remaining special sentinels25/0 rather than ordinary reflected board points. For a Black position with the usual starting checkers and dice1,2, PLAY 1 2 6/4 6/5 requests own6->4 and6->5, i.e. board19->21 and19->20; both are legal, non-hitting moves using both dice. Descending source/target canonical order gives OK 6/5 6/4, independent of input token order. A proposed final position is isolated from current state; the returned/generated legal candidate supplies canonical notation and is committed only after all checks. The generator search itself is outside this parsing routine: its legal collection is consumed by exact complete-position comparison, so evaluation, dice search and game/match scoring are unnecessary to explain recognition or failure non-mutation.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1861 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
