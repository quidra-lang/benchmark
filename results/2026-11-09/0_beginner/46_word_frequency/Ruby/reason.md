After normalization, the first cat occurrence creates count 1 and the second updates the same key to 2. These are occurrence counts, not distinct-word membership; the ranking and output do not participate in this update.

downcase and scan(/[a-z]+/) normalize tokens; tally constructs a new Hash and internally counts each key with an initial count of one, per documented Enumerable semantics. text is not mutated.

Normalization and the single frequency update establish first insertion and repeated increment. Ranking and word-frequency display are independent consumers and are omitted.
