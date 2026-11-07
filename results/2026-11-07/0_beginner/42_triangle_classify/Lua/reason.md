Split the current <= rejection into equality producing "degenerate" and strict < producing "not a triangle", before side/angle classification. The supplied [3,8,5] sorts to [3,5,8] and reaches equality. Only a+b>c proceeds into the unchanged valid-triangle classification path.

The copied sorted ordered table supplies a,b,c and result feeds the final output. Split the <= branch before the existing else; no change to original sides is needed.

Sorted sides and the rejection boundary locate the equality split; valid-triangle classifiers are retained only where needed to show the changed branch must precede them.
