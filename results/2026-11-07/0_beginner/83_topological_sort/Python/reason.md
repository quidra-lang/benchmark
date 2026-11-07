# Task B selection: 83_topological_sort / Python

## Answer requirements

Follow the local stopping block for list 2 when no eligible course remains. Identify how the candidate condition ends selection although untaken courses still exist, then how those remaining courses become the alphabetically ordered cycle-line data. Explain why the source does not remove from an empty candidate collection and how this differs from the all-taken case.

## Answer and source evidence

Python stops when ready is empty, so pop(0) cannot execute on an empty list; remaining courses are the sorted set difference. Quidra initializes selected to n, scans for an untaken zero-indegree course and breaks when selected stays n, before accessing it; remaining collects untaken entries from sorted names. For list2, the untaken course set supplies the alphabetically sorted cycle-line data. If all courses are taken, the same stop occurs but the remaining collection is empty. The chosen stop/read/render sites distinguish both cases without tracing prior removals.



Selected `main.py` lines: 9, 10, 17, 51, 54. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
