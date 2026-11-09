Maintain a one-based emitted-row ordinal separately from shape size i. The size sequence is 1,2,3,4,5,4,3,2,1, so the first shrinking row has ordinal 6 and size 4. Prefix "row k: " before the existing shape expression and advance the ordinal once per emitted row.

The existing row counter spans 0..2*n-2 and already supplies ordinal row+1. i is derived independently by the two sides of the conditional, so its shape computation stays intact.

The increasing/decreasing shape loops and row emission locate each ordinal update. Literal shape construction is retained where it shares the affected output line, rather than adding an entire independent numbering routine.
