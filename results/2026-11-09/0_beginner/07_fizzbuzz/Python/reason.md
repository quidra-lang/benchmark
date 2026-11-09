# Task B selection: 07_fizzbuzz / Python

## Answer requirements

For the numeric fallback at input 1, identify the source reference that supplies the current integer to the output expression and the binding to which that reference resolves. Distinguish that reference from the literal result strings. Focus on name resolution for this one expression rather than tracing all FizzBuzz decisions.

## Answer and source evidence

The output reference n resolves to the current loop binding, whose first value is 1. In the numeric fallback it supplies that integer, not a literal Fizz/Buzz string. The fallback is specified by the question; the remaining divisibility decisions are unnecessary for resolving this name.

The n operand of `text or n` is the numeric fallback.

Selected `main.py` lines: 1, 3. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
