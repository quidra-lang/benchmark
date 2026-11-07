After normalization, the first cat occurrence creates count 1 and the second updates the same key to 2. These are occurrence counts, not distinct-word membership; the ranking and output do not participate in this update.

The empty map and ??0 default give the first cat zero before +1; subsequent assignment replaces the integer at the same key. The regex/lowercase loop supplies normalized word values.

Normalization and the single frequency update establish first insertion and repeated increment. Ranking and word-frequency display are independent consumers and are omitted.
