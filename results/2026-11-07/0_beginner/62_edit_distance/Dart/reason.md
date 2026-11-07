At prefix lengths (2,2), matching i characters give replacement cost 0. The deletion and insertion candidates are both 2, while the matching diagonal is 1, so the cell becomes 1. A match changes the diagonal cost; it does not skip evaluation of the other candidate expressions.

The initialized boundary loops and nested recurrence supply the needed neighboring cells. The ternary selects only replacement cost; the inner math.min and outer math.min still evaluate the other alternatives.

The two input prefixes, initialized boundaries, equality cost and three candidate expressions establish cell (2,2). Later cells and final distance output cannot affect this local update.
