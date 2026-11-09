# Task B selection: 71_knapsack_01 / Quidra

## Answer requirements

Connect the knapsack DP base states, the 0-1 item-transition rule and traceback into selected item names. Explain how zero-item/zero-capacity initialization feeds the first tent decision and how later transitions read the preceding item stage so an item cannot be chosen twice. Show how traceback interprets those states and restores original item order for output. Focus on these stage dependencies rather than enumerating every table entry.

## Answer and source evidence

The zero-item row and zero-capacity column start at zero. For tent(weight10,value120), capacities below10 retain zero; capacity10 can compare zero against preceding-stage zero+120. Every include transition reads i-1, not the current stage, so a single item cannot be reused. Trace backward from the named capacity limit; a difference from the preceding stage marks that item chosen and subtracts its weight. Python reverses backward-selected indices; Quidra keeps an input-order boolean mask. These restore original order when selecting item names; unrelated final maximum/weight formatting is not required.



Selected `main.qui` lines: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
