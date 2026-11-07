# Task B selection: 15_gcd_lcm / Python

## Answer requirements

Explain the gcd operation from arguments (48, 180) to its returned result. Trace the successive Euclidean remainders, the update of the two working values and the zero-remainder termination. Explain why the working remainder must admit zero while the returned gcd is positive for these inputs, citing the source's actual arithmetic and any real type or runtime checks. Stop at the gcd result rather than tracing lcm formatting.

## Answer and source evidence

Euclidean states are (48,180), (180,48), (48,36), (36,12), (12,0); the result is 12. Each simultaneous assignment computes the remainder from the old a,b before replacing both. Zero is a legitimate remainder and terminates iteration, whereas the last nonzero a is positive for these positive inputs.

Python while b uses integer truth and int remainder values; this is runtime value behavior, not a static annotation.

Selected `main.py` lines: 1, 2, 3, 4. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
