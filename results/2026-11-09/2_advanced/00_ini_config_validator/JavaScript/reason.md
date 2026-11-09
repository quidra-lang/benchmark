# Task B — schema size normalization

The same answer requirements apply in every language: identify the size spelling grammar and case-insensitive binary unit scale; follow exact decimal-to-byte arithmetic and its failure exit; trace 1.5MB and 0.05KB; identify the successful source value representation and the normalization/error boundary; show how optional range bounds consume that successful numeric value, in order. Includes, inheritance, interpolation implementation and other scalar types are outside this routine-level question.

## JavaScript source evidence

`normalizeSize` returns either a number built from Number digit strings or null. The whole/fraction limits and binary factors keep accepted byte integers below the exact-integer limit of Number; the modulo guard rejects nonintegral bytes before division. normalizeScalar additionally rejects newline/tab input before size dispatch. checkedValue reports E_TYPE then returns null on failure; its range block uses the numeric value directly and reparses size bounds with normalizeScalar. Success returns an object containing that numeric value and a notation field; no string-valued byte payload is substituted.

For 1.5MB the whole part contributes 1×1048576 and the fractional part contributes (5×1048576)/10 = 524288 exactly, giving 1572864 integer bytes. For 0.05KB the fractional numerator is 5×1024 = 5120 with divisor 100; the nonzero remainder rejects the value before any range comparison. This becomes E_TYPE, not a rounded 51-byte value. A successful value is checked against any nonempty size bounds in the same byte unit; strict less-than/greater-than rejection makes equality acceptable. Without a range failure it crosses the normalization return boundary; the first failed parse or range check stops that operation.

## Necessity and alternatives

- `main.js`: 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 118, 119, 120, 123, 140, 141, 142, 143, 144, 145, 146, 147, 148, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188

The parser body is required because a name or return type alone cannot establish exact-byte divisibility, accepted spellings or unit factors. The selected dispatch, failure/return and range-consumer lines connect that computation to the requested operation. Type/standard-library conversion guarantees are used instead of copying their implementations; custom helpers needed to establish the grammar or arithmetic are retained. Whole scalar dispatches, list/string/date algorithms, callers that only carry an already expanded string, include processing and inheritance were considered and excluded because they add no evidence for these answer requirements. Diagnostic escaping/rendering internals are unnecessary to identify the first diagnostic code and precedence, so no exact escaped diagnostic text is claimed.

The excerpt has 1057 tokens under `metric/tokenizer.py`; omitting blank lines saves tokens over contiguous function blocks. A fresh excerpt-only review checked the grammar/constants, fractional rejection, success representation, parse-before-range precedence and range use against each requirement. No proposed program change was implemented, and this source review makes no compilation or runtime-correctness claim.
