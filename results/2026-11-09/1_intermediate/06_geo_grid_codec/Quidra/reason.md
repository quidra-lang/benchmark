# Task B selection — Quidra

## Answer requirements shared across languages

1. Explain set normalization: duplicates and descendants covered by an ancestor do not survive COMPACT.
2. Explain complete-sibling replacement and repetition across depths to a fixed point; give why one pass is insufficient.
3. Identify final COMPACT ordering and output representation.
4. Compare CHILDREN's TOO MANY limit with COMPACT's sibling completeness test and show whether the output cap limits merging.

## Selected source locations

- `main.qui`: 356, 357, 358, 359, 361, 362, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 698, 699, 700, 703, 704, 705, 706, 707, 708, 709, 710

## Evidence and language semantics

Duplicates collapse by cell identity before completeness is counted; an existing coarser ancestor covers and removes/skips a descendant. The selected ancestor calculation maps child coordinates into the coarser grid. Siblings at one precision with one immediate parent must number the product of the width and height ratios (or every generated child key must exist). Replacing them by their parent can complete another family at a coarser depth, so the changed/merged loop restarts until no replacement remains; one non-repeated sweep can miss a family created after it was visited. The final key orders precision ascending, y descending (north first), then x ascending (west first); the ordered codes are space separated. CHILDREN checks its own product against 100 before rendering; COMPACT performs its own membership/cardinality test and never calls CHILDREN, so that output guard does not prohibit merging a complete representable family. The selected set-size guard is only a necessary-completeness optimization.

Explicit same_cell supplies structural identity independently of object/reference representation. The mutable current sequence is replaced only after complete sibling counting. The insertion-sort condition establishes order directly, and result.join is the standard string join. Grid/codec internals are unnecessary for this general algorithm question.

## Minimization and alternatives

The final excerpt was checked against duplicates, ancestor coverage, a newly completed coarser family, ordering, and the independent CHILDREN cap. A lower-token candidate containing only the merge loop cannot establish deduplication/coverage or final ordering; CHILDREN alone cannot establish COMPACT behavior. The custom ancestor/identity implementation is necessary because its name is no language guarantee. Conversely, exact codec alphabets, numeric dimension tables, decoder branches, unrelated commands, and set-size early skips add no required fact and were excluded. The family test uses dimension ratios, so enumerating a particular example grid would cost more without answering an additional requirement.

The excerpt contains 1051 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
