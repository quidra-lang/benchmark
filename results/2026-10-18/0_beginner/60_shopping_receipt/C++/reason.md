# Task B selection: 60_shopping_receipt / C++

## Common answer requirements

Compute the food subtotal and its category tax from the actual food items, and follow that tax into payment separately from item lines.

## Source evidence

The food records/mask select milk, bread, apple and eggs. Price × quantity gives 396, 248, 512 and 268 yen, totaling 1424 yen. The item output prints that untaxed multiplication. The food tax applies integer division to 1424×8/100, producing 113 yen after category accumulation. Truncating each item tax instead gives 31+19+40+21 = 111 yen. The final-payment addition includes 113 yen alongside the pre-tax total and the other category’s contribution.

## Minimization

Unrelated category inputs and report lines can be omitted when independent. Shared lines are copied whole. The final payment expression is necessary; a separate print of its already computed result is not.

Selected complete lines of `main.cpp`: 6–17. The prior excerpt measured 467 tokens; this excerpt measures 455 with `metric/tokenizer.py`.
