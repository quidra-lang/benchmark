# Task B selection: 69_bowling_score / Quidra

## Answer requirements

Suppose a roll such as "10" arrives as a decimal string token rather than a numeric pin count. Identify where and how the ingestion conversion expression should produce its numeric value before existing comparisons or addition. Explain whether the present entry point already performs that conversion. Focus on one roll-token normalization; retain all frame rules.

## Answer and source evidence

The existing entry point is a numeric nested game array; neither loop binding performs text-to-number conversion. When a roll arrives as a decimal string, apply int(token) in ingestion before placing it in the numeric rolls sequence and before strike comparison or addition. The token "10" then becomes integer 10. Keep all frame advancement and bonus rules unchanged; those rules are not needed to locate this conversion boundary.



Selected `main.qui` lines: 1, 8, 15. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
