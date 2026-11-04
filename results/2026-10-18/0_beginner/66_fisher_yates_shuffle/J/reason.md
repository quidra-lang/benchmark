# Task B selection: 66_fisher_yates_shuffle / J

## Common answer requirements

Trace the two MINSTD updates, swap indices and affected cards; explain exact arithmetic and consumption for a self-swap.

## Supported analysis

The seed and descending loop yield (i,state,j) = (51,97,797,046,22) and (50,592,151,360,50). The second product is 4,720,761,207,466. The rank/suit order gives KC and TH at positions 51 and 22; QC stays at 50. The update precedes the swap with no self-swap guard, so both iterations consume a generator value. The maximum product is below 2^47, which fits the wide integer, arbitrary-precision or binary64 exact-integer arithmetic used here. Here the numeric representation is J machine integers on a 64-bit platform (or exact binary64 values below 2^53).

The excerpt is copied verbatim from `main.ijs`, in source order. Retained source lines: 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14.

## Minimization and alternatives

The resulting deck is a larger alternative that cannot establish the generator updates. Retain deck construction or numeric-to-card mapping, and discard the final terminator of a scope with no later dependent operation. The prior selection used 163 tokens; this selection uses 160 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
