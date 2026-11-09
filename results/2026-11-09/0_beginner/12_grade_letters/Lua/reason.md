Before a second counting pass, reset every grade cell to zero or recreate the initialized storage; otherwise each existing tally doubles. The present initialization already gives D a zero even though it receives no count update.

grades and counts have parallel five-element order with D at index 4. The increment and final indexed read show why all five cells must be reset.

Initialized grade storage and its count-update site are the two necessary locations. Repeating classification/output would not change the fact that a second pass adds to retained counts.
