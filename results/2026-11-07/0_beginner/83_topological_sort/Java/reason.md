# Task B selection: 83_topological_sort / Java

Candidate selection requires not-taken and zero remaining prerequisites. No candidate yields -1 or null, and the immediate break prevents removal/indexing of a nonexistent candidate. Remaining names filter not-taken in the already sorted name order and become the cycle line, whereas all-taken would leave that list empty.

The sorted names, eligibility/taken state, candidate stopping decision and remaining-name output suffice for the stopping block. Graph construction and original edge data are unnecessary because the no-eligible state is the question premise.

Selected complete source lines in `Main.java`: 8, 9, 10, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 33, 34, 35, 36. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
