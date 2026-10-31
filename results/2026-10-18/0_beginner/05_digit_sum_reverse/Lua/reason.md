# Task B selection: 05_digit_sum_reverse / Lua

## Common answer requirements

1. Trace the focused input 98000 and derive all fields of its output line.
2. Explain how zeros count as digits, add zero to the sum, and disappear only as leading zeros of the numeric reversed result.

## Answer supported by the excerpt

The complete line is `98000: digits=5 sum=17 reversed=89`. Arithmetic extraction visits digits 0, 0, 0, 8, 9 while remaining values become 9800, 980, 98, 9, 0: every iteration increments the digit count, zero contributes nothing to the sum, and reverse = reverse × 10 + digit keeps the initial reverse zero. String/digit-vector versions count all five positions, sum 9+8+0+0+0, and convert reversed 00089 back to the integer 89. The selected language implementation determines which of these equivalent traces applies.

## Source evidence and dependencies

Selected `main.lua` lines: 2,3,4,5,6,7,8. The excerpt preserves these complete lines in their original order and indentation.

The question provides the focused original input. The selected conversion or remainder loop, initial counters, reversal operation and final formatting determine its complete output. Every arithmetic update is needed to distinguish digit counting, digit addition and numeric reversal; a string version instead relies on the visible length/reversal/parse operations. Other input values do not affect this per-value trace.


Independent excerpt-only review found: The digit-processing loop is opened but its closing delimiter/end before final output is absent. Indentation is not a scope guarantee here, so the excerpt does not establish that exactly one complete output line follows the finished digit traversal. The final selection additionally retains original line(s) 6. The retained delimiter closes the shown loop, branch, or helper before the following operation. This is needed for the requested execution scope; indentation alone is not treated as a scope guarantee.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. Reading only the final output expression would leave the counters or reversed value unexplained. Reading the full input traversal adds unrelated numbers without changing this trace. The selected per-value computation and format are the sufficient smaller alternative.

The selected excerpt contains **121 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 121 tokens; the complete source contains 181 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
