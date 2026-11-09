# Task B selection — TypeScript

## Answer requirements shared across languages

1. Explain set normalization: duplicates and descendants covered by an ancestor do not survive COMPACT.
2. Explain complete-sibling replacement and repetition across depths to a fixed point; give why one pass is insufficient.
3. Identify final COMPACT ordering and output representation.
4. Compare CHILDREN's TOO MANY limit with COMPACT's sibling completeness test and show whether the output cap limits merging.

## Selected source locations

- `main.ts`: 343, 344, 345, 346, 347, 350, 351, 402, 403, 404, 405, 406, 407, 408, 409, 410, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 425, 426, 427, 428, 429, 432, 433, 434, 435, 436, 437, 438, 441, 442, 445, 446, 447, 448, 602, 603, 604, 605, 606, 607, 608, 609, 610

## Evidence and language semantics

Duplicates collapse by cell identity before completeness is counted; an existing coarser ancestor covers and removes/skips a descendant. The selected ancestor calculation maps child coordinates into the coarser grid. Siblings at one precision with one immediate parent must number the product of the width and height ratios (or every generated child key must exist). Replacing them by their parent can complete another family at a coarser depth, so the changed/merged loop restarts until no replacement remains; one non-repeated sweep can miss a family created after it was visited. The final key orders precision ascending, y descending (north first), then x ascending (west first); the ordered codes are space separated. CHILDREN checks its own product against 100 before rendering; COMPACT performs its own membership/cardinality test and never calls CHILDREN, so that output guard does not prohibit merging a complete representable family.

TypeScript uses JavaScript Map/Array semantics: the key string defines identity, set overwrites duplicates, every/some check membership and sort uses its comparator. Bigint arithmetic preserves grid ratios; static Cell annotations do not supply additional algorithmic behavior.

## Minimization and alternatives

The final excerpt was checked against duplicates, ancestor coverage, a newly completed coarser family, ordering, and the independent CHILDREN cap. A lower-token candidate containing only the merge loop cannot establish deduplication/coverage or final ordering; CHILDREN alone cannot establish COMPACT behavior. The custom ancestor/identity implementation is necessary because its name is no language guarantee. Conversely, exact codec alphabets, numeric dimension tables, decoder branches, unrelated commands, and set-size early skips add no required fact and were excluded. The family test uses dimension ratios, so enumerating a particular example grid would cost more without answering an additional requirement.

The excerpt contains 1038 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
