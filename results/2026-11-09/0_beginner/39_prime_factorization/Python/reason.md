# Task B selection: 39_prime_factorization / Python

## Answer requirements

For prime input 9973, locate the final remaining-factor condition and append operation. Explain why that decision supplies a factor even when trial division has collected none, and why a remaining value of 1 would not be appended. Focus on this decision rather than tracing all trial divisors.

## Answer and source evidence

The final condition tests remaining>1 and appends that remaining number as a factor. For prime input 9973, trial division has removed none, so remaining is 9973 and is appended even when the list is empty. A remaining value of 1 fails the comparison and is not a factor. Earlier trial divisors and output formatting add no evidence for this final decision.



Selected `main.py` lines: 12, 13. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
