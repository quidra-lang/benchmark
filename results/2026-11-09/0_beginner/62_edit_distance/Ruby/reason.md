At prefix lengths (2,2), matching i characters give replacement cost 0. The deletion and insertion candidates are both 2, while the matching diagonal is 1, so the cell becomes 1. A match changes the diagonal cost; it does not skip evaluation of the other candidate expressions.

Initialized boundary rows/columns and the nested recurrence establish dp[1,2]=dp[2,1]=dp[1,1]=1. The ternary only chooses cost; all three array elements are evaluated before .min.

The two input prefixes, initialized boundaries, equality cost and three candidate expressions establish cell (2,2). Later cells and final distance output cannot affect this local update.
