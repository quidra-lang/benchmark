The current source already supports nonempty all-negative arrays: current and best start at the first element rather than zero. For [-6,-3,-9], restart at -3 because extending gives -9, retain best -3, then reject the worse final candidate. The result is "max sum -3 at [1, 1]" in the reported zero-based convention.

The first-value initialization, restart/extend branch and strict best update establish nonempty behavior; range endpoints initialize to zero and print directly.

First-element initialization, restart/extend comparison, best update and reported indices establish the all-negative case. A zero-based sum initializer alternative is excluded by the actual source.
