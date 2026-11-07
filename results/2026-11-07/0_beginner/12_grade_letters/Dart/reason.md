Before a second counting pass, reset every grade cell to zero or recreate the initialized storage; otherwise each existing tally doubles. The present initialization already gives D a zero even though it receives no count update.

List.filled(5, 0) initializes every slot; letters maps index 3 to D. counts[grade]++ mutates cells and the output loop reads all five.

Initialized grade storage and its count-update site are the two necessary locations. Repeating classification/output would not change the fact that a second pass adds to retained counts.
