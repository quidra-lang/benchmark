# Task B selection: 86_convex_hull / Quidra

## Answer requirements

Explain the upper-chain construction operation from coordinate-sorted points to its completed chain. Identify the reverse traversal order and its first two points, then show how the current point, the last two chain points and the cross-product comparison control repeated removal and append. Explain why this reverses sorted order rather than original input order. Stop before lower/upper concatenation and area calculation.

## Answer and source evidence

Sort points lexicographically by coordinates, then reverse that sorted sequence for the upper chain. Its first points are (8,4) and (7,-1), not the last two original input points. Start an empty named upper-chain result, repeatedly remove its last point while at least two exist and cross(last2,last,current)<=0, then append current. Removing repeatedly eliminates non-left turns and collinear interiors before the next candidate. Stop when the upper chain is returned; lower-chain concatenation and area are outside this operation.



Selected `main.qui` lines: 3, 4, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 17, 18, 20. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
