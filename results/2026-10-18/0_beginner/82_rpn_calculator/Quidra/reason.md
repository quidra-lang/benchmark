# Task B selection: 82_rpn_calculator / Quidra

## Common answer requirements

[Code comprehension]

Trace the source's evaluation of expression 2, focusing on how it distinguishes negative integer tokens from subtraction and preserves operand order for division and subtraction. Explain how division of a negative value is made to truncate toward zero. Then identify where expression 3 stops with an error and why its remaining token is never evaluated.

## Answer supported by the selection

Only one-character tokens contained in "+-*/" enter the operator branch, so -17 and -3 go through integer parsing. In expression 2, -17 and 5 are pushed, then `.stack.take()` removes 5 as b and -17 as a. Integer division `a / b` truncates toward zero by the documented integer-division rule, yielding -3. Next 4 and -3 are pushed and multiplied to -12. The final subtraction removes -12 as b and -3 as a, giving -3-(-12)=9. The two takes therefore preserve older-left/newer-right operand order for both noncommutative operators. In expression 3, 1 and 2 are pushed and + replaces them with 3. At the following *, `len(stack) < 2` is true; assigning the underflow error and breaking exits token processing before its trailing 3 is parsed.

## Source evidence and minimization

The selected expression records are the two required inputs. The expression/token collection loops associate those strings with the operator-length test and signed parse branch. The stack initialization, both guarded takes, arithmetic branches and pushes establish operand order and trace state. The underflow assignment and break show that the final token of expression 3 is not evaluated. `import collections` supplies the mutable array push/take contracts. The zero-divisor branch is irrelevant to both requested traces, which have nonzero divisors; final output and leftover-operand checking occur after the relevant token processing and are omitted.

Locations in main source: L1, L3, L5, L6, L11, L12, L13, L15, L16, L17, L18, L19, L20, L21, L22, L23, L24, L25, L26, L27, L28, L29, L33, L34, L35, L36, L37, L38.

All selected lines are complete, verbatim and in source order. The selected source, the question, and documented language/library semantics support the answer. The full source is a sufficient alternative but includes the unrelated material identified above; the retained selection is a reviewed lower-token sufficient candidate, without a claim of exhaustive global minimality.

Measurement: Task A 574; Task B 330. Tokenizer: metric/tokenizer.py, unchanged. These counts and source selections do not establish compilation or execution of Task A.
