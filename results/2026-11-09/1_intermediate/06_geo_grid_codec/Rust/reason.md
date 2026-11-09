# Task B selection — Rust

## Answer requirements shared across languages

1. Explain set normalization: duplicates and descendants covered by an ancestor do not survive COMPACT.
2. Explain complete-sibling replacement and repetition across depths to a fixed point; give why one pass is insufficient.
3. Identify final COMPACT ordering and output representation.
4. Compare CHILDREN's TOO MANY limit with COMPACT's sibling completeness test and show whether the output cap limits merging.

## Selected source locations

- `main.rs`: 19, 20, 21, 22, 23, 123, 124, 125, 126, 359, 360, 361, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 375, 376, 377, 378, 381, 382, 383, 384, 385, 387, 388, 389, 393, 399, 454, 455, 456, 457, 458

## Evidence and language semantics

Duplicates collapse by cell identity before completeness is counted; an existing coarser ancestor covers and removes/skips a descendant. The selected ancestor calculation maps child coordinates into the coarser grid. Siblings at one precision with one immediate parent must number the product of the width and height ratios (or every generated child key must exist). Replacing them by their parent can complete another family at a coarser depth, so the changed/merged loop restarts until no replacement remains; one non-repeated sweep can miss a family created after it was visited. The final key orders precision ascending, y descending (north first), then x ascending (west first); the ordered codes are space separated. CHILDREN checks its own product against 100 before rendering; COMPACT performs its own membership/cardinality test and never calls CHILDREN, so that output guard does not prohibit merging a complete representable family.

Derived Cell equality/order makes BTreeSet unique by its fields. copied values and collected child/removal vectors permit later set mutation without aliasing the iterator; sort_by_key uses lexicographic tuples and standard join inserts spaces.

## Minimization and alternatives

The final excerpt was checked against duplicates, ancestor coverage, a newly completed coarser family, ordering, and the independent CHILDREN cap. A lower-token candidate containing only the merge loop cannot establish deduplication/coverage or final ordering; CHILDREN alone cannot establish COMPACT behavior. The custom ancestor/identity implementation is necessary because its name is no language guarantee. Conversely, exact codec alphabets, numeric dimension tables, decoder branches, unrelated commands, and set-size early skips add no required fact and were excluded. The family test uses dimension ratios, so enumerating a particular example grid would cost more without answering an additional requirement.

The excerpt contains 1114 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
