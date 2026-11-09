# Task B selection: 90_kruskal_mst / Quidra

## Answer requirements

Trace the complete Kruskal run from the thirteen stored edges through weight sorting, Union-Find decisions, accepted-edge output and the final total/skipped summaries. Use weights 5 and 6 to explain acceptance versus rejection, then identify the seventh accepted edge and why no later edge is examined. Derive the accepted edges in output order, their total weight and the skipped count, including endpoint normalization in the displayed names.

## Answer and source evidence

Accepted output order is G-H2, C-E3, A-C4, D-E5, A-B7, F-G8, E-H10. Weight5 joins D to the A/C/E tree; weight6 C-D is then a cycle and skipped. Weight9 B-C is also a cycle. The seventh accepted edge E-H10 joins the remaining components, then the accepted==7 stop prevents examining weights11,12,14,16. Total weight39 and skipped2. Endpoint labels are normalized ascending at output independently of stored edge direction. Selected data, sorting, find/union, counters and renderers cover the whole run.



Selected `main.qui` lines: 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
