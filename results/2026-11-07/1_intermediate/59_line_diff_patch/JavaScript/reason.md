# Task B selection — JavaScript

## Answer requirements shared across languages

1. Explain recognition of @@ -oldRange +newRange @@, signed range splitting, decimal parsing, omitted count1 and start0 permitted only for count0.
2. Trace context/deletion/addition body consumption against both counts and construction of the parsed hunk.
3. Compare X and X,0; distinguish malformed header, truncated body, bad/overflowing body and no-change errors with their reported line.

## Selected source locations

- `main.js`: 7, 384, 385, 386, 387, 388, 389, 390, 391, 392, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516

## Evidence and language semantics

NUMBER_PAIR is anchored; parseRange distinguishes undefined count capture from the string0. PatchHunk constructor maps old/new fields and initializes body. parsePatch reports malformed headers before body parsing, EOF as truncated, bad/overflowing lines at their own index, and all-context/no-change hunks at the header. A range X means startX,count1; X,0 means startX,count0 and consumes no line on that side. Thus0 alone is invalid, while0,0 is allowed by the range parser. Space-prefixed context contributes to both counts, minus only old and plus only new; parsing continues until both declared counts are met. EOF while either remains produces truncated hunk at the original header line; a malformed range/delimiter produces bad hunk header at that header, and an encountered invalid or overflowing body line produces bad hunk line at its own line. A new @@ line encountered before the body counts are met is a bad hunk line rather than EOF truncation. A body with no additions/deletions, including both counts zero, fails no changes. Hunk application, matching offsets/fuzz, document mutation and diff generation are outside this parse operation and were excluded.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1167 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
