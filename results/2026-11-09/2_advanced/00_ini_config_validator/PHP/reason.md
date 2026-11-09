# Task B — schema size normalization

The same answer requirements apply in every language: identify the size spelling grammar and case-insensitive binary unit scale; follow exact decimal-to-byte arithmetic and its failure exit; trace 1.5MB and 0.05KB; identify the successful source value representation and the normalization/error boundary; show how optional range bounds consume that successful numeric value, in order. Includes, inheritance, interpolation implementation and other scalar types are outside this routine-level question.

## PHP source evidence

`parseSize` returns ?int; regex \A/\z anchoring, lowercased factor lookup and intdiv after zero remainder establish the exact integer byte representation. parseScalar exposes string|int|bool|null but its size arm returns that int. normalize tests strict null then throws invalidValue/E_TYPE before checkRange and returning mixed value. Range reparses nonempty size bounds and compares the actual numeric value using >=/<= for success, which is equivalent to strict outside rejection. The ordinary intdiv contract avoids floating quotient truncation in accepted results.

For 1.5MB the whole part contributes 1×1048576 and the fractional part contributes (5×1048576)/10 = 524288 exactly, giving 1572864 integer bytes. For 0.05KB the fractional numerator is 5×1024 = 5120 with divisor 100; the nonzero remainder rejects the value before any range comparison. This becomes E_TYPE, not a rounded 51-byte value. A successful value is checked against any nonempty size bounds in the same byte unit; strict less-than/greater-than rejection makes equality acceptable. Without a range failure it crosses the normalization return boundary; the first failed parse or range check stops that operation.

## Necessity and alternatives

- `main.php`: 12, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 158, 159, 160, 169, 186, 187, 188, 189, 190, 191, 193, 194, 195, 196, 197, 198, 199, 200, 201, 204, 205, 206, 207, 208, 209, 212, 213, 214, 215, 216, 476, 477, 478, 479, 480, 481, 482, 483, 484, 516, 517, 518, 519, 520, 521

The parser body is required because a name or return type alone cannot establish exact-byte divisibility, accepted spellings or unit factors. The selected dispatch, failure/return and range-consumer lines connect that computation to the requested operation. Type/standard-library conversion guarantees are used instead of copying their implementations; custom helpers needed to establish the grammar or arithmetic are retained. Whole scalar dispatches, list/string/date algorithms, callers that only carry an already expanded string, include processing and inheritance were considered and excluded because they add no evidence for these answer requirements. Diagnostic escaping/rendering internals are unnecessary to identify the first diagnostic code and precedence, so no exact escaped diagnostic text is claimed.

The excerpt has 1166 tokens under `metric/tokenizer.py`; omitting blank lines saves tokens over contiguous function blocks. A fresh excerpt-only review checked the grammar/constants, fractional rejection, success representation, parse-before-range precedence and range use against each requirement. No proposed program change was implemented, and this source review makes no compilation or runtime-correctness claim.
