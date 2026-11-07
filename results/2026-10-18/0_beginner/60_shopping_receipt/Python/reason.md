# Task B selection: 60_shopping_receipt / Python

## Common answer requirements

Trace the actual food subtotal and category-level tax into the payment, distinguishing item subtotal printing.

## Source evidence

The food entries contribute milk 396, bread 248, apple 512, and eggs 268, totaling 1,424. The loop prints each price × quantity and adds that subtotal to its own category. Only after accumulation does integer division truncate 1,424 × 8 / 100 to 113. Payment starts from the sum of category totals and then adds each category tax.

## Minimization

General-only item literals and final formatting lines do not affect the food trace or establish the payment formula. The item subtotal output is retained because the question distinguishes it from taxation. Selected complete lines of `main.py`: 1, 2, 4, 5, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17.

## Current token measurement

Task A: **335 tokens**. Task B: **247 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
