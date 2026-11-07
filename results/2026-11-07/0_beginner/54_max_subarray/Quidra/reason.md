# Task B selection: 54_max_subarray / Quidra

## Answer requirements

Suppose all-negative arrays such as [-6, -3, -9] are additionally allowed while subarrays remain nonempty. Explain how initialization feeds Kadane's current-candidate recurrence and best-range update, and where any change is needed to prevent an artificial empty zero-sum candidate from winning. Use that array to connect the correct initial state, the restart decision and the resulting best range. Explain if the current source already satisfies the extension.

## Answer and source evidence

Both sources already start current/best at the first real element, never at an empty zero-sum candidate, so no algorithm change is needed. For [-6,-3,-9], initialize -6 at [0,0], restart at -3 when extending -6 is worse, and retain best=-3 at [1,1]; the final -9 cannot improve it. The recurrence and strict best update preserve a nonempty interval. The new input is supplied by the question, so the old example arrays and renderer are unnecessary.



Selected `main.qui` lines: 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
