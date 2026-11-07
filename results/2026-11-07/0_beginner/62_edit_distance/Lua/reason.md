At prefix lengths (2,2), matching i characters give replacement cost 0. The deletion and insertion candidates are both 2, while the matching diagonal is 1, so the cell becomes 1. A match changes the diagonal cost; it does not skip evaluation of the other candidate expressions.

The initialized boundaries and recurrence yield the same neighboring values. Lua treats numeric 0 as truthy, so and 0 or 1 correctly gives zero for equality; math.min arguments are all evaluated.

The two input prefixes, initialized boundaries, equality cost and three candidate expressions establish cell (2,2). Later cells and final distance output cannot affect this local update.
