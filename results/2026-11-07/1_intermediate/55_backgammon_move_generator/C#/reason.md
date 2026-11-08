# Task B selection — C#

## Answer requirements shared across languages

1. Trace numeric, bar and off PLAY syntax, optional hit marks/path repetition, and Black own-number to board-point correspondence.
2. Explain construction of a temporary proposed position, rule rejection and recognition by equality with generated legal plays.
3. Give a valid Black example and its final canonical notation, identifying success-only mutation and invalid/unmatched exits.

## Selected source locations

- `Program.cs`: 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 129, 130, 131, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 431, 566, 567, 576, 577, 578, 579, 580, 581, 582, 583

## Evidence and language semantics

ParsePlay maps locations/repetitions into Move pairs without a side-dependent numeric transform. Position input stores Black at24-i, so own p corresponds to board25-p. ChoosePlay clones the array and compares an exact PositionKey against Legal; Require throws on invalid input before ApplyPlay. Notation sorts/merges/groups accepted legal moves. Numeric notation always uses the moving player's own numbering: Black own point p corresponds to board point25-p, with bar/off remaining special sentinels25/0 rather than ordinary reflected board points. For a Black position with the usual starting checkers and dice1,2, PLAY 1 2 6/4 6/5 requests own6->4 and6->5, i.e. board19->21 and19->20; both are legal, non-hitting moves using both dice. Descending source/target canonical order gives OK 6/5 6/4, independent of input token order. A proposed final position is isolated from current state; the returned/generated legal candidate supplies canonical notation and is committed only after all checks. The generator search itself is outside this parsing routine: its legal collection is consumed by exact complete-position comparison, so evaluation, dice search and game/match scoring are unnecessary to explain recognition or failure non-mutation.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 2848 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
