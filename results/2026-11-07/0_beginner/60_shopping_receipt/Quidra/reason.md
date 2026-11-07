# Task B selection: 60_shopping_receipt / Quidra

## Answer requirements

Connect the food-item subtotal aggregation with category-level tax truncation and the final payment calculation. Use the actual food items to derive the food category total and its integer tax, identify where truncation occurs, and explain why applying it after aggregation differs from truncating each item's tax. Show how that food tax combines with untaxed item subtotals and the general-category tax without taxing an amount twice.

## Answer and source evidence

Food subtotals are 198*2=396,248,128*4=512,268, totaling 1424. Category tax truncates 1424*8/100=113.92 to 113 yen; per-item truncation would instead give 31+19+40+21=111. General subtotal is 932 and general tax 93. Add untaxed subtotals 2356 and the two taxes 113+93 once, yielding payment 2562. The selected category mapping, subtotal accumulation and later integer tax/payment operations establish the boundary; individual item output and final presentation are unnecessary.



Selected `main.qui` lines: 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
