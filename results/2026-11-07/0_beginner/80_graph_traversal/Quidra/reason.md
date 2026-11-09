# Task B selection: 80_graph_traversal / Quidra

## Answer requirements

Explain the complete graph-reporting path from the unordered edge list through undirected adjacency construction and sorted neighbors to DFS, BFS and component output. Trace how vertex 7 is first reached in each traversal, then account for vertices outside vertex 0's component during component discovery. Derive both traversal orders and the ordered component lists, identifying source rules for visit timing, component numbering and formatting.

## Answer and source evidence

The edges are inserted in both directions and neighbors visited ascending. DFS order is 0 2 7 5 3 8; vertex7 is first reached recursively from2. BFS order is 0 2 5 7 3 8; marking on enqueue reaches7 from2 before any later duplicate enqueue. The first component sorts to 0 2 3 5 7 8, then the outer ascending unvisited scan starts at1 and finds sorted component 1 4 6. The report prints two components numbered1 and2. Selected construction, visit timing, resets and renderers establish all requested stages.

adjacency_lists with undirected=true supplies documented sorted neighbor lists; writable references expose visited/order updates through DFS recursion.

Selected `main.qui` lines: 4, 5, 6, 7, 8, 9, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
