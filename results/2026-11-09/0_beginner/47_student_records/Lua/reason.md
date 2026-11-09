Normalize the actual name field before sorting and display consumers, removing only its outer ASCII spaces while retaining case. Keep scores and total/rank comparisons unchanged; " Tanaka " must become "Tanaka" before name tie-breaking and output.

student[1] is the name used by a[1]<b[1] and by io.write. Normalize that field during the existing pre-sort student traversal, preserving numeric score fields and total.

The name field at construction and its sort/display consumers locate the common normalization point. Subject-score arithmetic need not change because it never reads the name.
