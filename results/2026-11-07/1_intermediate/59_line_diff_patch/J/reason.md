# Task B selection — J

## Answer requirements shared across languages

1. Explain recognition of @@ -oldRange +newRange @@, signed range splitting, decimal parsing, omitted count1 and start0 permitted only for count0.
2. Trace context/deletion/addition body consumption against both counts and construction of the parsed hunk.
3. Compare X and X,0; distinguish malformed header, truncated body, bad/overflowing body and no-change errors with their reported line.

## Selected source locations

- `main.ijs`: 5, 25, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369

## Evidence and language semantics

numberPair checks one/two fields with one-to-four digits; parseRange extends an omitted count with1 and enforces0/0. hunkHeader returns [line,oldStart,oldCount,newStart,newCount]. parsePatch consumes both counts, accumulates kinds/texts and uses patchError to distinguish header line, current bad body line, truncation and no changes. A range X means startX,count1; X,0 means startX,count0 and consumes no line on that side. Thus0 alone is invalid, while0,0 is allowed by the range parser. Space-prefixed context contributes to both counts, minus only old and plus only new; parsing continues until both declared counts are met. EOF while either remains produces truncated hunk at the original header line; a malformed range/delimiter produces bad hunk header at that header, and an encountered invalid or overflowing body line produces bad hunk line at its own line. A new @@ line encountered before the body counts are met is a bad hunk line rather than EOF truncation. A body with no additions/deletions, including both counts zero, fails no changes. Hunk application, matching offsets/fuzz, document mutation and diff generation are outside this parse operation and were excluded.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1038 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
