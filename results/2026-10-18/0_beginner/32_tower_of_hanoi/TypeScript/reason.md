# Task B selection: 32_tower_of_hanoi / TypeScript

Identify the disk-count argument to change; verify the peg roles, recursive move order and disk numbers, and how the unchanged move and total lines are produced.

The initial call must use 5 in place of 4, with source A, target C and auxiliary B. The base case stops at zero. For a positive disk count, the first call moves the smaller disks to the auxiliary peg, the middle print moves disk n to the target, and the second call moves the smaller disks from the auxiliary peg to the target. Each middle move contributes one to the count, giving 2⁵ − 1 = 31. Keep both output statements and their formats.

The recursive parameter binding makes the peg permutations unambiguous. The final output either includes the call directly or consumes its result or shared count. Selecting the call alone in the latter case cannot establish the final output; main wrappers and output setup beyond these dependencies are unnecessary.

Source: `main.ts`, original lines 1–5, 8–9. The previous excerpt measures 164 tokens; this evidence set measures 182 tokens.
