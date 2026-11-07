# Task B: 60_shopping_receipt / J

Food subtotals are milk 396, bread 248, apple 512 and eggs 268, totaling 1424. Truncating 1424×8/100 gives food tax 113. Per-item truncation would give 31+19+40+21=111, two less, so truncation belongs after category aggregation. General subtotal is 495+437=932, tax 93; payment adds untaxed subtotals once plus the two taxes: 1424+932+113+93=2562.

The category masks sum subtotal values first, then <. floors the category-rate products. The final total adds subtotal and taxes once.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L10,L11,L12,L13,L14.

- L2: `names =. ;:'milk notebook bread apple detergent eggs'`
- L3: `prices =. 198 165 248 128 437 268`
- L4: `quantities =. 2 3 1 4 1 1`
- L5: `food =. 1 0 1 1 0 1`
- L6: `subtotals =. prices*quantities`
- L10: `foodtotal =. +/food#subtotals`
- L11: `generaltotal =. +/(-.food)#subtotals`
- L12: `foodtax =. <.(foodtotal*8)%100`
- L13: `generaltax =. <.(generaltotal*10)%100`
- L14: `total =. foodtotal+generaltotal+foodtax+generaltax`

Minimization: Item price/quantity/category data, subtotal aggregation, tax truncation and final addition are necessary for the requested numerical comparison. Per-item receipt formatting is omitted when separately written. The selected complete original lines, in source order, cost 163 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 225, and the complete source costs 332. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
