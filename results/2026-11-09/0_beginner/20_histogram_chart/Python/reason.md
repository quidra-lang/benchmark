# Task B selection: 20_histogram_chart / Python

## Answer requirements

Suppose each asterisk represents two counted items, rounding an odd count upward to one more asterisk, while the numeric count after the bar remains unscaled. Explain the dependency between retrieving a day/count pair, computing its displayed bar length and constructing the output line. Use Mon's count 7 and Tue's count 12 to show the two rounding cases, and identify how the original count and day order survive the change.

## Answer and source evidence

Use the paired day/count iteration unchanged. Replace only the repetition length by ceil(count/2), implemented for nonnegative integers as (count+1)//2 or Quidra integer division (count+1)/2; leave the final numeric count field unscaled. Mon=7 produces four stars and Tue=12 produces six. The paired iteration preserves the day order and retains count for the original numeric field; the question provides these two counts.



Selected `main.py` lines: 3, 4. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
