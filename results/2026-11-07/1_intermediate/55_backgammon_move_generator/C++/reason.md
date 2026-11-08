# Task B selection — C++

## Answer requirements shared across languages

1. Trace numeric, bar and off PLAY syntax, optional hit marks/path repetition, and Black own-number to board-point correspondence.
2. Explain construction of a temporary proposed position, rule rejection and recognition by equality with generated legal plays.
3. Give a valid Black example and its final canonical notation, identifying success-only mutation and invalid/unmatched exits.

## Selected source locations

- `main.cpp`: 17, 18, 19, 21, 32, 33, 34, 67, 68, 69, 71, 72, 88, 89, 90, 91, 92, 93, 94, 95, 96, 101, 102, 103, 104, 105, 106, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 342, 343, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401, 402, 403, 404, 405, 406, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 818, 819, 820, 821, 822, 823, 842, 843, 844, 845, 846, 847, 848, 849

## Evidence and language semantics

Move is a pair of own points; Bar25/Off0 and numeric syntax are handled by parsePlay. boardValue and opposing establish Black board25-p. validatePlay copies Position, validates and compares final positions, throwing before commit on failure. canonicalKey plus notation derive the accepted play text. Numeric notation always uses the moving player's own numbering: Black own point p corresponds to board point25-p, with bar/off remaining special sentinels25/0 rather than ordinary reflected board points. For a Black position with the usual starting checkers and dice1,2, PLAY 1 2 6/4 6/5 requests own6->4 and6->5, i.e. board19->21 and19->20; both are legal, non-hitting moves using both dice. Descending source/target canonical order gives OK 6/5 6/4, independent of input token order. A proposed final position is isolated from current state; the returned/generated legal candidate supplies canonical notation and is committed only after all checks. The generator search itself is outside this parsing routine: its legal collection is consumed by exact complete-position comparison, so evaluation, dice search and game/match scoring are unnecessary to explain recognition or failure non-mutation.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text. Whitespace-only lines outside source literals and explicit line continuations are omitted: they contribute tokens but no evidence for the answer. Literal content is preserved, and files with ambiguous quote or multiline-literal syntax are left unchanged by this step.

The excerpt contains 2930 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
