# Task B selection: 15_gcd_lcm / JavaScript

## Answer requirements

Trace Euclidean remainders and the stopping condition for the given pair, then show how the result is used in division before multiplication.

## Evidence and answer

The named gcd parameters are local bindings; the simultaneous destructuring uses the old a and b for the remainder and returns a when b reaches zero. The caller’s original a and b are then used for left-associative a / divisor * b.

The (a,b) states are (48,180) → (180,48) → (48,36) → (36,12) → (12,0), with remainders 48, 36, 12 and 0. The GCD is 12 and the LCM is (48 ÷ 12) × 180 = 720. The question gives the pair in order; the unrelated pair literals and outer traversal are not required to trace these operands.

## Minimization

Selected complete lines of `main.js`: 1, 2, 3, 7, 8. The excerpt preserves their text, indentation and order.

Adding the input collection or outer iteration repeats the pair from the question and adds other cases. Removing the helper body would lose the actual remainder sequence and stopping rule; the helper’s name alone does not establish them. The previous excerpt contained 159 tokens; the selected excerpt contains **84 tokens** using `metric/tokenizer.py`.
