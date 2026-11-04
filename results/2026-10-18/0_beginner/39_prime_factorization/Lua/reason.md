# Task B selection: 39_prime_factorization / Lua

Trace the trial divisor range and failed divisions for 9973, then derive why the remaining factor has neither an exponent nor a separator in the printed line.

The starting divisor is 2. No integer from 2 through 99 divides 9973, so the remainder test never enters the division body and the factor exponent remains zero for every trial. The divisor advances until 100² = 10000 exceeds 9973. The remaining value is still 9973, so the greater-than-one branch emits it as plain digits. No earlier factor has been emitted. The complete line is `9973 = 9973`.

The question provides 9973. The original-to-working-value assignment, trial bounds and factor guards matter; other inputs do not. An empty list joined with a single factor produces no separator; in streaming versions the first-factor flag remains unchanged. The exponent formatting of earlier factors need not be read beyond the lines required to identify their guarded insertion.

Source: `main.lua`, original lines 2–15. The previous excerpt measures 264 tokens; this evidence set measures 241 tokens.
