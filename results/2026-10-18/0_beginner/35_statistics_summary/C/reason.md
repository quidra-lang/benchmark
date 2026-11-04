# Task B selection: 35_statistics_summary / C

Locate the population denominator and distinguish that edit from any other use of the length.

Use 10 as the divisor for the accumulated squared differences before taking the square root. Where the code derives the divisor from a collection size, use the collection size minus one at this division; where it uses a literal, replace that literal while retaining real division. Leave the mean calculation, the per-value differences and accumulation, and the existing field and formatter in place. Do not change a shared count used by the mean.

Only the denominator changes. Where the expression is an unnamed argument in a multiline print call, the format identifies its destination. The mean, accumulation, input literals, and formatting internals are otherwise outside the edit. The unchanged formatter is used under the Task B assumptions.

The format and deviation are separated in source, so both the format's last slot and the argument supplying it are retained.

Source: `main.c`, original lines 31–32. The previous excerpt measures 44 tokens; this evidence set measures 84 tokens.
