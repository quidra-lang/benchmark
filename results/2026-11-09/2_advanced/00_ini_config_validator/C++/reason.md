# Task B — schema size normalization

The same answer requirements apply in every language: identify the size spelling grammar and case-insensitive binary unit scale; follow exact decimal-to-byte arithmetic and its failure exit; trace 1.5MB and 0.05KB; identify the successful source value representation and the normalization/error boundary; show how optional range bounds consume that successful numeric value, in order. Includes, inheritance, interpolation implementation and other scalar types are outside this routine-level question.

## C++ source evidence

`parse_size` returns std::optional<long long>; regex_match and the explicit binary factor map establish the spelling, while stoll and remainder/divisor operations preserve exact integer bytes. parse_number dispatches size and parse_scalar places the accepted integer in Value.number; that field is explicitly long long. normalize throws invalid_value/E_TYPE before invoking check_range and returning Value. bound_value reuses scalar parsing for size bounds, and the selected less lambda compares numeric fields for this non-date kind; absent bounds are skipped. to_lower shows the actual ASCII case conversion used for the unit lookup.

For 1.5MB the whole part contributes 1×1048576 and the fractional part contributes (5×1048576)/10 = 524288 exactly, giving 1572864 integer bytes. For 0.05KB the fractional numerator is 5×1024 = 5120 with divisor 100; the nonzero remainder rejects the value before any range comparison. This becomes E_TYPE, not a rounded 51-byte value. A successful value is checked against any nonempty size bounds in the same byte unit; strict less-than/greater-than rejection makes equality acceptable. Without a range failure it crosses the normalization return boundary; the first failed parse or range check stops that operation.

## Necessity and alternatives

- `main.cpp`: 23, 26, 27, 33, 64, 65, 66, 67, 68, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 269, 273, 274, 275, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 321, 322, 336, 337, 341, 342, 344, 345, 346, 347, 353, 354, 356, 357, 358, 359, 360, 361, 362, 366, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 672, 673, 674, 675, 677, 678, 679, 680, 681, 682, 683, 684, 685, 686, 687, 688
- `emitter.hpp`: 13, 14, 18

The parser body is required because a name or return type alone cannot establish exact-byte divisibility, accepted spellings or unit factors. The selected dispatch, failure/return and range-consumer lines connect that computation to the requested operation. Type/standard-library conversion guarantees are used instead of copying their implementations; custom helpers needed to establish the grammar or arithmetic are retained. Whole scalar dispatches, list/string/date algorithms, callers that only carry an already expanded string, include processing and inheritance were considered and excluded because they add no evidence for these answer requirements. Diagnostic escaping/rendering internals are unnecessary to identify the first diagnostic code and precedence, so no exact escaped diagnostic text is claimed.

The excerpt has 1721 tokens under `metric/tokenizer.py`; omitting blank lines saves tokens over contiguous function blocks. A fresh excerpt-only review checked the grammar/constants, fractional rejection, success representation, parse-before-range precedence and range use against each requirement. No proposed program change was implemented, and this source review makes no compilation or runtime-correctness claim.
