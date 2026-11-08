# Task B selection — R

## Answer requirements shared across languages

1. Explain set normalization: duplicates and descendants covered by an ancestor do not survive COMPACT.
2. Explain complete-sibling replacement and repetition across depths to a fixed point; give why one pass is insufficient.
3. Identify final COMPACT ordering and output representation.
4. Compare CHILDREN's TOO MANY limit with COMPACT's sibling completeness test and show whether the output cap limits merging.

## Selected source locations

- `main.R`: 12, 13, 14, 15, 16, 19, 276, 277, 278, 279, 280, 281, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 329, 330, 331, 332, 333, 337, 339, 340, 341, 342, 343, 511, 512, 513, 549, 550, 551, 552, 553, 554, 555

## Evidence and language semantics

Duplicates collapse by cell identity before completeness is counted; an existing coarser ancestor covers and removes/skips a descendant. The selected ancestor calculation maps child coordinates into the coarser grid. Siblings at one precision with one immediate parent must number the product of the width and height ratios (or every generated child key must exist). Replacing them by their parent can complete another family at a coarser depth, so the changed/merged loop restarts until no replacement remains; one non-repeated sweep can miss a family created after it was visited. The final key orders precision ascending, y descending (north first), then x ascending (west first); the ordered codes are space separated. CHILDREN checks its own product against 100 before rendering; COMPACT performs its own membership/cardinality test and never calls CHILDREN, so that output guard does not prohibit merging a complete representable family. The selected set-size guard is only a necessary-completeness optimization.

The hash environment is a key-value set using the selected cell_key/num representation; replacement under the same key deduplicates and rm removes it. fd explicitly implements floor division. order(p,-y,x) is lexicographic and paste with collapse supplies separating spaces; the encoder itself is not needed.

## Minimization and alternatives

The final excerpt was checked against duplicates, ancestor coverage, a newly completed coarser family, ordering, and the independent CHILDREN cap. A lower-token candidate containing only the merge loop cannot establish deduplication/coverage or final ordering; CHILDREN alone cannot establish COMPACT behavior. The custom ancestor/identity implementation is necessary because its name is no language guarantee. Conversely, exact codec alphabets, numeric dimension tables, decoder branches, unrelated commands, and set-size early skips add no required fact and were excluded. The family test uses dimension ratios, so enumerating a particular example grid would cost more without answering an additional requirement.

The excerpt contains 1182 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
