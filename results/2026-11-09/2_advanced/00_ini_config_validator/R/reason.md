# Task B — schema size normalization

The same answer requirements apply in every language: identify the size spelling grammar and case-insensitive binary unit scale; follow exact decimal-to-byte arithmetic and its failure exit; trace 1.5MB and 0.05KB; identify the successful source value representation and the normalization/error boundary; show how optional range bounds consume that successful numeric value, in order. Includes, inheritance, interpolation implementation and other scalar types are outside this routine-level question.

## R source evidence

`parse_size` returns an integer-valued numeric scalar or NULL. The selected matches helper anchors the grammar, lower_ascii uses chartr, and split_keep/cut_first establish that decimal pieces are split at the literal dot. decimal is as.numeric: the representation is R numeric rather than an imposed integer type, with the bounded integer magnitudes exactly representable. normalize_value returns a list containing error/type_error E_TYPE before range on NULL. The success boundary is list(value=value); range uses that scalar numeric measure and reuses parse_scalar for nonempty size bounds. No rounded displayed value drives acceptance.

For 1.5MB the whole part contributes 1×1048576 and the fractional part contributes (5×1048576)/10 = 524288 exactly, giving 1572864 integer bytes. For 0.05KB the fractional numerator is 5×1024 = 5120 with divisor 100; the nonzero remainder rejects the value before any range comparison. This becomes E_TYPE, not a rounded 51-byte value. A successful value is checked against any nonempty size bounds in the same byte unit; strict less-than/greater-than rejection makes equality acceptable. Without a range failure it crosses the normalization return boundary; the first failed parse or range check stops that operation.

## Necessity and alternatives

- `main.R`: 12, 13, 14, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 119, 120, 125, 130, 131, 132, 133, 134, 135, 136, 138, 139, 140, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175
- `lexer.R`: 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18

The parser body is required because a name or return type alone cannot establish exact-byte divisibility, accepted spellings or unit factors. The selected dispatch, failure/return and range-consumer lines connect that computation to the requested operation. Type/standard-library conversion guarantees are used instead of copying their implementations; custom helpers needed to establish the grammar or arithmetic are retained. Whole scalar dispatches, list/string/date algorithms, callers that only carry an already expanded string, include processing and inheritance were considered and excluded because they add no evidence for these answer requirements. Diagnostic escaping/rendering internals are unnecessary to identify the first diagnostic code and precedence, so no exact escaped diagnostic text is claimed.

The excerpt has 1490 tokens under `metric/tokenizer.py`; omitting blank lines saves tokens over contiguous function blocks. A fresh excerpt-only review checked the grammar/constants, fractional rejection, success representation, parse-before-range precedence and range use against each requirement. No proposed program change was implemented, and this source review makes no compilation or runtime-correctness claim.
