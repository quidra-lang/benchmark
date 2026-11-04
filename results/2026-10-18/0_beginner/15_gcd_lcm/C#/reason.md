# Task B selection: 15_gcd_lcm / C#

## Answer requirements

Trace Euclidean remainders and the stopping condition for the given pair, then show how the result is used in division before multiplication.

## Evidence and answer

Gcd takes integer values by value; its while block rebinds a and b using the remainder. The caller retains the original operands and interpolates a / g * b, which groups left to right. The method’s outer braces and the removed foreach brace carry no arithmetic evidence.

The (a,b) states are (48,180) → (180,48) → (48,36) → (36,12) → (12,0), with remainders 48, 36, 12 and 0. The GCD is 12 and the LCM is (48 ÷ 12) × 180 = 720. The question gives the pair in order; the unrelated pair literals and outer traversal are not required to trace these operands.

## Minimization

Selected complete lines of `Program.cs`: 6, 8, 9, 10, 11, 12, 13, 14, 19, 20. The excerpt preserves their text, indentation and order.

Adding the input collection or outer iteration repeats the pair from the question and adds other cases. Removing the helper body would lose the actual remainder sequence and stopping rule; the helper’s name alone does not establish them. The previous excerpt contained 230 tokens; the selected excerpt contains **144 tokens** using `metric/tokenizer.py`.
