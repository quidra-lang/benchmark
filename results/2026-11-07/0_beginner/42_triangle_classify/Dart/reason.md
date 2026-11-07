Split the current <= rejection into equality producing "degenerate" and strict < producing "not a triangle", before side/angle classification. The supplied [3,8,5] sorts to [3,5,8] and reaches equality. Only a+b>c proceeds into the unchanged valid-triangle classification path.

The rejection branch currently writes and continues. Add a separate equality write-and-continue before the valid path, retain a strict less-than rejection, and keep the later side/angle write for valid triangles.

Sorted sides and the rejection boundary locate the equality split; valid-triangle classifiers are retained only where needed to show the changed branch must precede them.
