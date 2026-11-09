# Task B selection: 12_grade_letters / Python

## Answer requirements

Suppose the same grade-count storage is reused for a second report on the same ten scores. Identify where and how its initial values or missing-key defaults must be reestablished so counts do not double and the absent D grade still prints 0. Relate the initialization, one count update and the read of the D count in the actual local counting block. State if the present initialization already supplies the required zero.

## Answer and source evidence

Before counting a second report, restore all five grade entries to zero. The existing initialization already supplies zero for D, so an absent grade still prints 0. Each score contributes one increment to its chosen grade; reusing the previously accumulated storage without clearing would double the nonzero counts.

dict.fromkeys("ABCDF",0) creates all five keys. The update is counts[grade] += 1 and items() emits those stored entries, including D.

Selected `main.py` lines: 2, 14, 16, 17. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
