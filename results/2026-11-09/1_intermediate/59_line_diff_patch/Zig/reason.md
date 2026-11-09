# Task B selection — Zig

## Answer requirements shared across languages

1. Explain recognition of @@ -oldRange +newRange @@, signed range splitting, decimal parsing, omitted count1 and start0 permitted only for count0.
2. Trace context/deletion/addition body consumption against both counts and construction of the parsed hunk.
3. Compare X and X,0; distinguish malformed header, truncated body, bad/overflowing body and no-change errors with their reported line.

## Selected source locations

- `main.zig`: 567, 568, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651

## Evidence and language semantics

parseNumber/Pairs enforce1..4 ASCII digits and no third component. Optional second orelse1 preserves explicit0; start0 requires count0. Header validates all delimiters/signs and returns fields. parsePatch allocates body data, checks required-line EOF separately, validates kind/count capacity, rejects no changes and returns hunks or a formatted failure. A range X means startX,count1; X,0 means startX,count0 and consumes no line on that side. Thus0 alone is invalid, while0,0 is allowed by the range parser. Space-prefixed context contributes to both counts, minus only old and plus only new; parsing continues until both declared counts are met. EOF while either remains produces truncated hunk at the original header line; a malformed range/delimiter produces bad hunk header at that header, and an encountered invalid or overflowing body line produces bad hunk line at its own line. A new @@ line encountered before the body counts are met is a bad hunk line rather than EOF truncation. A body with no additions/deletions, including both counts zero, fails no changes. Hunk application, matching offsets/fuzz, document mutation and diff generation are outside this parse operation and were excluded.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1625 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
