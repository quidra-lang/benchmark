# Task B selection: 15_gcd_lcm / Go

## Answer requirements

Trace Euclidean remainders and the stopping condition for the given pair, then show how the result is used in division before multiplication.

## Evidence and answer

The caller reads p[0] then p[1]. The helper takes int64 values by value and the multiple assignment evaluates a%b using the old operands before replacing them. Its return follows the zero-guarded loop. The caller groups a / g * b left to right.

The (a,b) states are (48,180) → (180,48) → (48,36) → (36,12) → (12,0), with remainders 48, 36, 12 and 0. The GCD is 12 and the LCM is (48 ÷ 12) × 180 = 720. The question gives the pair in order; the unrelated pair literals and outer traversal are not required to trace these operands.

## Minimization

Selected complete lines of `main.go`: 5, 6, 7, 8, 9, 14, 15, 16. The excerpt preserves their text, indentation and order.

Adding the input collection or outer iteration repeats the pair from the question and adds other cases. Removing the helper body would lose the actual remainder sequence and stopping rule; the helper’s name alone does not establish them. The previous excerpt contained 180 tokens; the selected excerpt contains **101 tokens** using `metric/tokenizer.py`.

## Current token measurement

Task A: **267 tokens**. Task B: **101 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
