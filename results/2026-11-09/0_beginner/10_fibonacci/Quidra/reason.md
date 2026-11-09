# Task B selection: 10_fibonacci / Quidra

## Answer requirements

Explain the logical operation that generates the requested Fibonacci sequence and its total, from the term-count value 30 to the sequence and sum made available for output. Identify the initial terms, the next-term update, the count boundary and the total update, using F(3) as a concrete check. Explain from the actual declarations or operations whether terms and totals remain exact integer quantities, distinguishing value behavior from any static guarantee. Do not list all thirty terms.

## Answer and source evidence

The sequence starts 1,1 and takes the sum of its last two terms for the next term, so F(3)=2. The generation limit is thirty terms, with each generated/current term included once in a separate total. Python computes the completed-list total afterward; Quidra updates it during generation. These integer additions retain exact integral values.

The inferred a, b and total are arbitrary-precision int bindings. The inclusive loop 1..30 has thirty iterations; total accumulates the pre-update a each time. Printing is outside the requested operation.

Selected `main.qui` lines: 1, 2, 6, 7. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
