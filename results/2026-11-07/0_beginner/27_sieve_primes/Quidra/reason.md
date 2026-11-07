# Task B selection: 27_sieve_primes / Quidra

## Answer requirements

Suppose the flag for integer k is stored at physical position k+1 instead of the current mapping. Explain how to adapt the sieve operation from its inclusive limit through flag allocation/initialization, composite marking and retrieval of prime values. Use integers 0, 1, 7, 49 and 200 to identify the relevant translated accesses and bounds. Preserve the same sieve and prime ordering, distinguishing integer labels from physical storage positions.

## Answer and source evidence

Keep integer labels 0..limit, with limit=200, but translate every flag access for k to k+1. Allocate limit+2 positions, leaving physical position 0 unused. Initialize flags for 0 and 1 at positions 1 and 2. Prime 7 is retrieved at 8 and composite 49 is marked at 50; integer 200 maps to 201. Arithmetic loop labels and prime output values stay unshifted, and inclusive limit bounds still refer to labels, not physical positions. The selected allocation, initialization, marking and retrieval show every affected site.



Selected `main.qui` lines: 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
