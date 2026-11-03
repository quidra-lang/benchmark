# Task B selection: 83_topological_sort / Quidra

Identify how to choose the alphabetically last currently eligible course after every removal while keeping termination and the ascending cycle remainder.

Names are sorted in ascending order, and each scan currently stops at the first eligible index. Reversing the scan direction, while retaining its first-match break, selects the alphabetically last eligible course. The eligibility predicate continues to be reconsidered by the enclosing existing algorithm. The selected course is appended to the result. The sorted name array itself should remain ascending so the unchanged cycle enumeration retains its required order.

The selected lines establish the sorted-name representation, scan bounds, first-match decision and selected-name use. Input graphs, unchanged indegree updates and formatting do not need modification and add no evidence about the changed tie rule. The explicit array mutation uses the documented `push` contract.

Selected complete source lines in order: 4, 5, 13, 14, 15, 16, 17, 21.

Every selected line is copied verbatim from `main.qui` in source order. The reviewed alternatives were the relevant contiguous span and complete source; each adds unchanged context. This is a reviewed sufficient selection, not a proof of a global minimum. Task B assumes Task A correctness as required by the benchmark README.

Task A uses 748 tokens. Task B uses 104 tokens under the unchanged `metric/tokenizer.py`. Source selection and token measurement do not establish compilation or execution.
