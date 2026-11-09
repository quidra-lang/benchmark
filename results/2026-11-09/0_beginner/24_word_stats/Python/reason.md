# Task B selection: 24_word_stats / Python

## Answer requirements

Suppose this source is ported to a setting where dividing two integer values truncates. Identify where and how the average-word-length division expression must ensure a real-number quotient while the count operands remain exact integers. Cite the actual operands and any existing conversion or real-valued operation, explaining if that expression already meets the requirement.

## Answer and source evidence

The division uses the total number of word characters as numerator and the number of words as denominator. Their integer counts remain exact. Ensure at least one operand is converted to a real-valued type before division in a setting where integer division truncates; presentation precision alone cannot restore the fraction.

Python `/` already produces a real-number quotient from integer operands. The named total is the numerator; len(words) is the denominator.

Selected `main.py` lines: 15, 16. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
