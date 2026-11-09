# Task B selection — C#

## Answer requirements shared across languages

1. Explain recognition of @@ -oldRange +newRange @@, signed range splitting, decimal parsing, omitted count1 and start0 permitted only for count0.
2. Trace context/deletion/addition body consumption against both counts and construction of the parsed hunk.
3. Compare X and X,0; distinguish malformed header, truncated body, bad/overflowing body and no-change errors with their reported line.

## Selected source locations

- `Program.cs`: 455, 459, 503, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590

## Evidence and language semantics

NumberPair and ParseRange distinguish omitted count from explicit0. ParseHunkHeader validates exactly four space-separated parts and both signed ranges. Parse tracks oldSeen/newSeen, stores prefix-stripped body tuples, and throws distinct header/body/truncated/no-changes errors before returning hunks. A range X means startX,count1; X,0 means startX,count0 and consumes no line on that side. Thus0 alone is invalid, while0,0 is allowed by the range parser. Space-prefixed context contributes to both counts, minus only old and plus only new; parsing continues until both declared counts are met. EOF while either remains produces truncated hunk at the original header line; a malformed range/delimiter produces bad hunk header at that header, and an encountered invalid or overflowing body line produces bad hunk line at its own line. A new @@ line encountered before the body counts are met is a bad hunk line rather than EOF truncation. A body with no additions/deletions, including both counts zero, fails no changes. Hunk application, matching offsets/fuzz, document mutation and diff generation are outside this parse operation and were excluded.

## Minimization and alternatives

Each selected expression establishes a requested fact or its data dependency. The excerpt was read without unselected implementation details: removing the kind extraction, bounds/coordinate/default condition, state update, or output expression would lose that fact. A larger enclosing routine, unrelated commands, declarations with inferable types, and implementations of standard primitives were considered and excluded; no alternative smaller expression in this source establishes the same facts. Complete lines retain their original syntax even when one line includes incidental text.

The excerpt contains 1339 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
