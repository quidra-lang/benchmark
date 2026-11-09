Split the current <= rejection into equality producing "degenerate" and strict < producing "not a triangle", before side/angle classification. The supplied [3,8,5] sorts to [3,5,8] and reaches equality. Only a+b>c proceeds into the unchanged valid-triangle classification path.

triple.sort binds ordered a,b,c while output uses triple. Insert an equality result branch into the existing if/else boundary; retain side/angle processing only in its valid else path.

Sorted sides and the rejection boundary locate the equality split; valid-triangle classifiers are retained only where needed to show the changed branch must precede them.
