After normalization, the first cat occurrence creates count 1 and the second updates the same key to 2. These are occurrence counts, not distinct-word membership; the ranking and output do not participate in this update.

The empty frequencies table gives nil for the first cat; or 0 substitutes zero before +1. Later reads return 1; assigning frequencies[word] replaces that numeric cell and mutates the table.

Normalization and the single frequency update establish first insertion and repeated increment. Ranking and word-frequency display are independent consumers and are omitted.
