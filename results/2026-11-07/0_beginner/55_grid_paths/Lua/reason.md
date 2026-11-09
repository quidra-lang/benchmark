The top-left cell starts with count 1, representing the one empty route that is already at the start, rather than zero reachable routes. The source supplies this same base state for both obstacle-disabled and obstacle-enabled counting.

The first grid cell is open, so the obstacle branch cannot take it; the row==1 and column==1 branch assigns 1. count_paths(false/true) reuse that code.

The start-cell assignment and the calls for both obstacle settings establish one empty path in each run. The full interior DP recurrence is unnecessary to explain that base value.
