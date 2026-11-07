# Task B selection: 05_digit_sum_reverse / Quidra

## Answer requirements

Trace the complete path of input 98000 from the given input collection to its printed result line. Explain how the source obtains its decimal digits, counts the zeros as digits, accumulates the digit sum, and forms the reversed integer without leading zeros. Derive the complete output line, including labels and spacing, and identify the source operations for each stage.

## Answer and source evidence

Input 98000 becomes the decimal sequence 9,8,0,0,0. Its count is 5, the sum is 17, and reversing then converting to an integer gives 89 by discarding leading zeros. The line is `98000: digits=5 sum=17 reversed=89`. The collection and loop establish the original input; the digit extraction, named count, sum, reverse conversion and output establish every requested stage.

digits() creates numeric decimal digits; string(original) provides decimal text for the reverse slice, and int converts that text.

Selected `main.qui` lines: 1, 3, 4, 5, 6, 7, 8. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
