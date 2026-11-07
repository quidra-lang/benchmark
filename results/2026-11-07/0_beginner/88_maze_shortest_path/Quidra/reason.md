# Task B selection: 88_maze_shortest_path / Quidra

## Answer requirements

Suppose stored parent values must uniformly be (row, column) pairs rather than flattened cell numbers. In the first-discovery parent-write block and its corresponding reconstruction read, identify the current representation and where and how both sides and the start marker must agree on the new value contract. Explain if the source already satisfies it; preserve BFS discovery order and the path itself.

## Answer and source evidence

Both sources currently store flattened predecessor cell numbers, with the start pointing to itself. Store (predecessor_row,predecessor_column) at first discovery, give start its own coordinate pair, and have reconstruction consume that pair consistently (or flatten it only when continuing to use the existing flat queue/maze indices). Parent allocation/default and unseen/goal tests must also use a compatible pair sentinel or optional absence. Neither source already satisfies the pair value contract. Keep first-discovery timing and neighbor order unchanged; grid content adds no representation evidence.



Selected `main.qui` lines: 18, 19, 22, 23, 24, 25, 30, 31, 32, 35, 36, 39. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
