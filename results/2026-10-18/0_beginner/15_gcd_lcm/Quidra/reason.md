# Task B selection: 15_gcd_lcm / Quidra

## Answer requirements

Trace Euclidean remainders and the stopping condition for the given pair, then show how the result is used in division before multiplication.

## Evidence and answer

The explicit comparison `while b != 0` continues while `b` is nonzero and stops when it is zero. The simultaneous assignment evaluates `b` and `a % b` with the old operands before rebinding the helper's local value parameters. The helper returns `a`; the caller uses this result as `divisor` with its original operands. Since `/` and `*` have equal precedence and associate to the left, `a / divisor * b` divides exactly before multiplying by `b`.

The (a,b) states are (48,180) → (180,48) → (48,36) → (36,12) → (12,0), with remainders 48, 36, 12 and 0. The GCD is 12 and the LCM is (48 ÷ 12) × 180 = 720. The question gives the pair in order; the unrelated pair literals and outer traversal are not required to trace these operands.

## Minimization

Selected complete lines of `main.qui`: 1, 2, 3, 4, 7, 8. The excerpt preserves their text, indentation and order.

Adding the input collection or outer iteration repeats the pair from the question and adds other cases. The helper's signature, loop, and return establish how the given operands become the GCD; the caller's two lines show where that value is used and in which order the arithmetic is performed. The selected excerpt contains **70 tokens** using `metric/tokenizer.py`, down from 80 in the previous revision.

Measurement: Task A 186; Task B 70. Tokenizer: metric/tokenizer.py, unchanged.
