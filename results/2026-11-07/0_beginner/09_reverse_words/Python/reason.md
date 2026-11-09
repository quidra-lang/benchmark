# Task B selection: 09_reverse_words / Python

## Answer requirements

Compare the neighboring operations that produce the two reversal outputs. Identify the sequence each operation reverses and the unit of one sequence element: a character or a whole word. Use the final word "line" and its preceding space to explain why four letters reverse individually in the first result but remain one word in the second, and how the second result rejoins the reversed words with single spaces.

## Answer and source evidence

The first operation reverses the sentence by single-character positions: the letters in line become enil and its preceding space remains a separate character. The second splits at spaces, reverses the resulting word sequence, and joins with one space, so line remains intact as the first word. The question provides the relevant last word; the separate full sentence literal adds no necessary operation evidence.



Selected `main.py` lines: 2, 3. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
