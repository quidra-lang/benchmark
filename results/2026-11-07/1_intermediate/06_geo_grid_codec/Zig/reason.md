# Task B selection — Zig

## Answer requirements shared across languages

1. Explain set normalization: duplicates and descendants covered by an ancestor do not survive COMPACT.
2. Explain complete-sibling replacement and repetition across depths to a fixed point; give why one pass is insufficient.
3. Identify final COMPACT ordering and output representation.
4. Compare CHILDREN's TOO MANY limit with COMPACT's sibling completeness test and show whether the output cap limits merging.

## Selected source locations

- `main.zig`: 117, 118, 119, 121, 122, 127, 128, 421, 425, 439, 440, 441, 442, 443, 444, 445, 446, 447, 500, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 518, 520, 521, 522, 523, 524, 525, 526, 527, 528, 530, 531, 532, 533, 534, 535, 536, 537, 538, 541, 542, 543, 544, 545, 549, 550, 551, 552, 553

## Evidence and language semantics

Duplicates collapse by cell identity before completeness is counted; an existing coarser ancestor covers and removes/skips a descendant. The selected ancestor calculation maps child coordinates into the coarser grid. Siblings at one precision with one immediate parent must number the product of the width and height ratios (or every generated child key must exist). Replacing them by their parent can complete another family at a coarser depth, so the changed/merged loop restarts until no replacement remains; one non-repeated sweep can miss a family created after it was visited. The final key orders precision ascending, y descending (north first), then x ascending (west first); the ordered codes are space separated. CHILDREN checks its own product against 100 before rendering; COMPACT performs its own membership/cardinality test and never calls CHILDREN, so that output guard does not prohibit merging a complete representable family.

AutoArrayHashMap keys are the fixed-size integer array produced by key, so put replaces equal keys. orderedRemove mutates the set; the changed loop restarts after each successful family. std.mem.sort uses Cell.less; explicit writeByte supplies spaces. The dispatch branch identifies CHILDREN as the remaining operation after PARENT.

## Minimization and alternatives

The final excerpt was checked against duplicates, ancestor coverage, a newly completed coarser family, ordering, and the independent CHILDREN cap. A lower-token candidate containing only the merge loop cannot establish deduplication/coverage or final ordering; CHILDREN alone cannot establish COMPACT behavior. The custom ancestor/identity implementation is necessary because its name is no language guarantee. Conversely, exact codec alphabets, numeric dimension tables, decoder branches, unrelated commands, and set-size early skips add no required fact and were excluded. The family test uses dimension ratios, so enumerating a particular example grid would cost more without answering an additional requirement.

The excerpt contains 1469 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
