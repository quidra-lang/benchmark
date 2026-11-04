# Task B selection: 06_factorial_table / TypeScript

## Answer requirements

Locate the factorial range and determine which representation, operations or output would need to change to preserve exact results through 15!.

## Evidence and answer

The inclusive loop bound changes from 12 to 15. The factorial initializer gives the variable type number, and every factorial through 15! = 1307674368000 is below 2^53 and exact in that representation. The recurrence does not need changing to reach the new endpoint, and ordinary interpolation of a number at this magnitude is decimal. Its separate update and output are not required change sites.

## Minimization

Selected complete lines of `main.ts`: 1, 2. The excerpt preserves their text, indentation and order.

The loop header alone does not reveal the integer representation. Selecting the full loop body adds unchanged calculations or output that do not introduce another edit. The previous excerpt contained 53 tokens; the selected excerpt contains **35 tokens** using `metric/tokenizer.py`.
