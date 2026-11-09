Before a second counting pass, reset every grade cell to zero or recreate the initialized storage; otherwise each existing tally doubles. The present initialization already gives D a zero even though it receives no count update.

to_h explicitly includes A B C D F with value 0; counts[grade] += 1 is the update and counts.each reads every grade including D.

Initialized grade storage and its count-update site are the two necessary locations. Repeating classification/output would not change the fact that a second pass adds to retained counts.
