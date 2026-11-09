# Task B selection: 35_statistics_summary / Quidra

## Answer requirements

Explain the mode-selection operation from the eleven sample values to the selected value. Identify how frequencies are formed, how candidates are compared or ordered, and how an equal-frequency tie resolves toward the smaller value. Derive the selected mode for the actual samples and distinguish a strict frequency improvement from an equal-frequency candidate, using the source's real equality or secondary-order handling.

## Answer and source evidence

The samples contain 85 three times and every other value once, so the mode is 85. Python sorts candidates ascending before max(..., key=count); max keeps its first candidate on an equal key, so the smaller value wins a frequency tie. Quidra frequencies() forms value counts and ranked_entries orders by decreasing count then increasing key, so the first entry has the same tie rule. Strictly greater frequency wins; equal frequency is resolved by ascending value, not by replacing it with a larger equal-count candidate. Unrelated summary statistics are excluded.



Selected `main.qui` lines: 3, 8, 9. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
