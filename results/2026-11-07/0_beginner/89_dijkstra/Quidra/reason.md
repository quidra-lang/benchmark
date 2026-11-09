# Task B selection: 89_dijkstra / Quidra

## Answer requirements

Suppose the initial unreached-distance value must be the finite sentinel 1000 instead of the source's present sentinel. Identify where and how to change that initialization expression while preserving the source vertex's zero. Use the given positive edge weights to justify that 1000 is greater than every finite shortest distance here. Focus on this default-value change; do not change relaxation or path output.

## Answer and source evidence

Replace the unreached fill value by1000 while retaining the separate source-distance assignment0. The graph has seven vertices with positive edge weights at most9, so a finite shortest path can be simple and uses at most six edges, giving an upper bound54<1000. Hence no finite shortest distance collides with the sentinel. Relaxation and path output need no changes for this input. The input node/edge bounds and the initialization/source override suffice.

Quidra currently fills distance with -1 then sets distance[start]=0; the finite sentinel remains above all valid candidates here.

Selected `main.qui` lines: 3, 5, 6, 9, 12, 13. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
