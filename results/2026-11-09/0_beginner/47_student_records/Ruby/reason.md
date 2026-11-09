Normalize the actual name field before sorting and display consumers, removing only its outer ASCII spaces while retaining case. Keep scores and total/rank comparisons unchanged; " Tanaka " must become "Tanaka" before name tie-breaking and output.

The map destructures name and scores before constructing [name,total] and sorting by name. Normalize name at that map construction, so both later destructured output and sort key consume the same cleaned string.

The name field at construction and its sort/display consumers locate the common normalization point. Subject-score arithmetic need not change because it never reads the name.
