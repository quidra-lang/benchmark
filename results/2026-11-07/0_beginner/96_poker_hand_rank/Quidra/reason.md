# Task B selection: 96_poker_hand_rank / Quidra

## Answer requirements

Follow the local rank-representation block for T and A through ordinary high-card values and ace-low-straight comparison values. State the numeric encoding actually used, or its equivalent explicit ordering, identify the low-ace special-case condition and explain how its resulting comparison sequence differs from an ordinary ace-high hand. Distinguish rank values from the final hand's printed position; do not trace full category selection.

## Answer and source evidence

The rank alphabet encodes 2..9 as2..9, T as10, J11,Q12,K13,A14. An ace-low straight is exactly distinct ranks [2,3,4,5,14]; its comparison sequence becomes [5,4,3,2,1], treating ace as1 for that sequence. Ordinary ace-high hands retain14 in their count/rank-ordered sequence. These internal rank values are distinct from the final one-based printed hand position. Category selection and final ranking output are outside this local representation question.



Selected `main.qui` lines: 5, 10, 11, 14, 16, 17, 35, 36, 37. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
