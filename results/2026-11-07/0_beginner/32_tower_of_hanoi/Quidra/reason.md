# Task B selection: 32_tower_of_hanoi / Quidra

## Answer requirements

Explain the recursive Hanoi operation from its disk-count and peg-role arguments to its emitted moves and move count. Use the top-level four-disk call to show the two recursive subproblems, the intervening move and the base case. Identify how the first recursive call reassigns source/target/auxiliary roles and whether those label arguments change caller bindings or shared peg storage in this implementation. Ground the count combination and sharing behavior in the source.

## Answer and source evidence

The four-disk call maps n=4, source=A, target=C, auxiliary=B. First move three disks A to B with C auxiliary, then emit disk 4 A to C, then move three disks B to C with A auxiliary. At n=0 return zero; combine the two returned counts with the one intervening move, giving 15 moves for four disks. Peg arguments are label values, with no writes through shared peg storage or caller bindings.

The signature takes string values rather than writable references; Quidra value arguments do not expose caller storage.

Selected `main.qui` lines: 1, 2, 3, 4, 5, 6, 7, 9. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
