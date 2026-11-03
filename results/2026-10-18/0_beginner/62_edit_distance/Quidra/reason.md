# Task B selection: 62_edit_distance / Quidra

## Common answer requirements

[Code comprehension]

Using the source, explain how the edit-distance table represents transformations involving an empty prefix, then trace the calculation for flaw and lawn through the table entries needed for the final distance. Identify which code handles matching characters and which alternatives account for insertion, deletion, and replacement. Relate those alternatives to their prefix subproblems rather than merely giving the distance.

## Answer supported by the selection

The row comprehension creates rows indexed i=0 through len(a), each beginning with i; therefore dp[i][0]=i counts deletions to an empty target. The generated integer range assigned to the first row sets dp[0][j]=j, counting insertions from an empty source. For flaw/lawn, rows 0 through 4 are [0,1,2,3,4], [1,1,2,3,4], [2,1,2,3,4], [3,2,1,2,3], and [4,3,2,1,2]. Matching l, a and w uses cost zero along dp[2][1]=1, dp[3][2]=1 and dp[4][3]=1. At dp[4][4], deletion gives dp[3][4]+1=4, insertion gives dp[4][3]+1=2 and replacement gives dp[3][3]+1=3, so the final distance is 2. The three array elements are deletion from the previous source prefix, insertion after the previous target prefix, and matching/replacing the last character after the two shorter prefixes; `min_all` chooses their minimum. The table remains two-dimensional and records all prefix pairs.

## Source evidence and minimization

Only the flaw/lawn input record is needed. The tuple loop supplies a and b, length bindings define table extents, and both initialization expressions establish empty-prefix states. Both nested loops, character-cost decision and complete recurrence establish the order and all predecessor cases. `import math` supplies the min_all contract. Other word pairs and the printing statement do not affect this trace.

Locations in main source: L1, L3, L5, L9, L10, L11, L12, L13, L14, L15, L16, L17, L18.

All selected lines are complete, verbatim and in source order. The selected source, the question, and documented language/library semantics support the answer. The full source is a sufficient alternative but includes the unrelated material identified above; the retained selection is a reviewed lower-token sufficient candidate, without a claim of exhaustive global minimality.

Measurement: Task A 369; Task B 288. Tokenizer: metric/tokenizer.py, unchanged. These counts and source selections do not establish compilation or execution of Task A.

Execution verification: the revised program compiled and its stdout matched the valid historical Quidra program exactly.
