Normalize the actual name field before sorting and display consumers, removing only its outer ASCII spaces while retaining case. Keep scores and total/rank comparisons unchanged; " Tanaka " must become "Tanaka" before name tie-breaking and output.

The student is a (String,List<int>) record; name is .$1 and scores .$2. Construct cleaned-name records before students.sort, retaining the score list; the comparator and later print then read the cleaned .$1.

The name field at construction and its sort/display consumers locate the common normalization point. Subject-score arithmetic need not change because it never reads the name.
