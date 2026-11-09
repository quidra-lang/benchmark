# Task B selection — Julia

## Answer requirements shared across languages

1. Trace numeric, bar and off PLAY syntax, optional hit marks/path repetition, and Black own-number to board-point correspondence.
2. Explain construction of a temporary proposed position, rule rejection and recognition by equality with generated legal plays.
3. Give a valid Black example and its final canonical notation, identifying success-only mutation and invalid/unmatched exits.

## Selected source locations

- `main.jl`: 40, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 211, 212, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 472, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499

## Evidence and language semantics

parse_play maps conceptual own points0..25 to tuples; array access adds1. Board display uses Black array column26-boardPoint, proving board=25-own. validate_play copies the matrix and compares legal final matrices. Syntax/error/unmatched paths return without make_play!, while canonical generates the accepted play notation. Numeric notation always uses the moving player's own numbering: Black own point p corresponds to board point25-p, with bar/off remaining special sentinels25/0 rather than ordinary reflected board points. For a Black position with the usual starting checkers and dice1,2, PLAY 1 2 6/4 6/5 requests own6->4 and6->5, i.e. board19->21 and19->20; both are legal, non-hitting moves using both dice. Descending source/target canonical order gives OK 6/5 6/4, independent of input token order. A proposed final position is isolated from current state; the returned/generated legal candidate supplies canonical notation and is committed only after all checks. The generator search itself is outside this parsing routine: its legal collection is consumed by exact complete-position comparison, so evaluation, dice search and game/match scoring are unnecessary to explain recognition or failure non-mutation.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1957 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
