# Task B selection: 49_bracket_balance / Python

## Answer requirements

Locate the decision that classifies a scanned character as a bracket token or ignores it. For the plus sign in (a + b) * [c - d], explain why it causes no stack action but still occupies an original character position. Cite the recognition and position expression; do not assume that nonbrackets were filtered out and positions renumbered.

## Answer and source evidence

The plus sign is absent from both opening and closing bracket sets, so it reaches the ignore path and performs no stack push/pop. Scanning enumerates/indexes the original string rather than a bracket-filtered string; therefore plus and every other nonbracket still occupy original zero-based character positions. Recognition conditions and the original-position error expression establish that convention. Other mismatched examples and final result formatting are irrelevant.



Selected `main.py` lines: 10, 14, 15, 16, 17, 18, 19, 21. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
