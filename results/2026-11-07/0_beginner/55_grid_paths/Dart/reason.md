The top-left cell starts with count 1, representing the one empty route that is already at the start, rather than zero reachable routes. The source supplies this same base state for both obstacle-disabled and obstacle-enabled counting.

mode runs 0 and 1. The open first grid cell bypasses the obstacle continue; r==0 && c==0 assigns 1 then skips recurrence in each mode.

The start-cell assignment and the calls for both obstacle settings establish one empty path in each run. The full interior DP recurrence is unnecessary to explain that base value.
