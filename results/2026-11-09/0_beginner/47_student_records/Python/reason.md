# Task B selection: 47_student_records / Python

## Answer requirements

Suppose a name field may contain leading/trailing ASCII spaces, such as " Tanaka ", and those outer spaces must be discarded while preserving letter case. Identify where and how a local normalization expression should act on the name before its existing consumers, using the actual field binding. Do not change scores or ranking rules.

## Answer and source evidence

Normalize the name field at record creation, before it participates in either sort keys or output. Strip only outer ASCII space characters and preserve case, so ` Tanaka ` becomes `Tanaka`; scores and ranking comparison directions stay unchanged.

Apply name.strip(" ") in the generator that creates (name,total), before the key reads row[0].

Selected `main.py` lines: 10, 11. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
