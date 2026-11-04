# Task B selection: 15_gcd_lcm / PHP

## Answer requirements

Trace Euclidean remainders and the stopping condition for the given pair, then show how the result is used in division before multiplication.

## Evidence and answer

The int parameters are passed by value. The destructuring update evaluates the old operands together until b is exactly zero, then the function returns a. The caller uses intdiv on its original a and the returned divisor before multiplication by b.

The (a,b) states are (48,180) → (180,48) → (48,36) → (36,12) → (12,0), with remainders 48, 36, 12 and 0. The GCD is 12 and the LCM is (48 ÷ 12) × 180 = 720. The question gives the pair in order; the unrelated pair literals and outer traversal are not required to trace these operands.

## Minimization

Selected complete lines of `main.php`: 3, 5, 6, 7, 8, 12, 13. The excerpt preserves their text, indentation and order.

Adding the input collection or outer iteration repeats the pair from the question and adds other cases. Removing the helper body would lose the actual remainder sequence and stopping rule; the helper’s name alone does not establish them. The previous excerpt contained 185 tokens; the selected excerpt contains **110 tokens** using `metric/tokenizer.py`.
