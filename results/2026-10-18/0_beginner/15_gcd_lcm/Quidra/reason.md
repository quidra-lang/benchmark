# Task B selection: 15_gcd_lcm / Quidra

## Answer requirements

Trace Euclidean remainders and the stopping condition for the given pair, then show how the result is used in division before multiplication.

## Evidence and answer

The helper takes int value parameters and rebinds them simultaneously using the old operands until b=0. It returns a; the caller computes the parenthesized exact integer division a / divisor before multiplying by the unchanged b.

The (a,b) states are (48,180) → (180,48) → (48,36) → (36,12) → (12,0), with remainders 48, 36, 12 and 0. The GCD is 12 and the LCM is (48 ÷ 12) × 180 = 720. The question gives the pair in order; the unrelated pair literals and outer traversal are not required to trace these operands.

## Minimization

Selected complete lines of `main.qui`: 1, 2, 3, 4, 7, 8. The excerpt preserves their text, indentation and order.

Adding the input collection or outer iteration repeats the pair from the question and adds other cases. Removing the helper body would lose the actual remainder sequence and stopping rule; the helper’s name alone does not establish them. The previous excerpt contained 166 tokens; the selected excerpt contains **80 tokens** using `metric/tokenizer.py`.

Measurement: Task A 196; Task B 80. Tokenizer: metric/tokenizer.py, unchanged.
