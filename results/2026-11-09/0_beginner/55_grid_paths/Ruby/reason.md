The top-left cell starts with count 1, representing the one empty route that is already at the start, rather than zero reachable routes. The source supplies this same base state for both obstacle-disabled and obstacle-enabled counting.

dp[0]=1 is unconditional inside paths; the two call sites invoke that same operation with false and true, so the base assignment is shared.

The start-cell assignment and the calls for both obstacle settings establish one empty path in each run. The full interior DP recurrence is unnecessary to explain that base value.
