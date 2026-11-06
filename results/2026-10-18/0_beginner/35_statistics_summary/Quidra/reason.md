# Task B selection: 35_statistics_summary / Quidra

Locate the population denominator and distinguish that edit from any other use of the length.

Use 10 as the divisor for the accumulated squared differences before taking the square root. Where the code derives the divisor from a collection size, use the collection size minus one at this division; where it uses a literal, replace that literal while retaining real division. Leave the mean calculation, the per-value differences and accumulation, and the existing field and formatter in place. Do not change a shared count used by the mean.

Only the denominator changes. Where the expression is an unnamed argument in a multiline print call, the format identifies its destination. The mean, accumulation, input literals, and formatting internals are otherwise outside the edit. The unchanged formatter is used under the Task B assumptions.

The source binds the converted length once and uses it in both divisions. Adjusting that binding would alter the mean.

Source: `main.qui`, original lines 2, 5–6, 16. The previous excerpt measures 31 tokens; this evidence set measures 48 tokens.

Measurement: Task A 266; Task B 48. Tokenizer: metric/tokenizer.py, unchanged.
