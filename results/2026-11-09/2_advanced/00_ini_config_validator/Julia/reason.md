# Task B — schema size normalization

The same answer requirements apply in every language: identify the size spelling grammar and case-insensitive binary unit scale; follow exact decimal-to-byte arithmetic and its failure exit; trace 1.5MB and 0.05KB; identify the successful source value representation and the normalization/error boundary; show how optional range bounds consume that successful numeric value, in order. Includes, inheritance, interpolation implementation and other scalar types are outside this routine-level question.

## Julia source evidence

`parse_size` returns a parsed Int expression or nothing, using anchored regex captures, a binary factor Dict and exact remainder followed by ÷. parse_scalar dispatches size directly. normalize! throws invalid_value/E_TYPE on nothing before check_range and returns the numeric value. The range closure applies the same parse_scalar to size bounds, uses value itself as measure and returns normally on inclusive bound acceptance; otherwise it throws E_RANGE. Julia Int parsing and arithmetic, not a declared annotation imposed on the untyped source, establish the source value contract.

For 1.5MB the whole part contributes 1×1048576 and the fractional part contributes (5×1048576)/10 = 524288 exactly, giving 1572864 integer bytes. For 0.05KB the fractional numerator is 5×1024 = 5120 with divisor 100; the nonzero remainder rejects the value before any range comparison. This becomes E_TYPE, not a rounded 51-byte value. A successful value is checked against any nonempty size bounds in the same byte unit; strict less-than/greater-than rejection makes equality acceptable. Without a range failure it crosses the normalization return boundary; the first failed parse or range check stops that operation.

## Necessity and alternatives

- `main.jl`: 9, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 125, 138, 139, 159, 160, 161, 162, 163, 164, 166, 167, 168, 169, 170, 171, 172, 173, 175, 177, 178, 179, 180, 181, 182, 373, 374, 375, 376, 377, 378, 379, 380, 412, 413, 414, 415

The parser body is required because a name or return type alone cannot establish exact-byte divisibility, accepted spellings or unit factors. The selected dispatch, failure/return and range-consumer lines connect that computation to the requested operation. Type/standard-library conversion guarantees are used instead of copying their implementations; custom helpers needed to establish the grammar or arithmetic are retained. Whole scalar dispatches, list/string/date algorithms, callers that only carry an already expanded string, include processing and inheritance were considered and excluded because they add no evidence for these answer requirements. Diagnostic escaping/rendering internals are unnecessary to identify the first diagnostic code and precedence, so no exact escaped diagnostic text is claimed.

The excerpt has 960 tokens under `metric/tokenizer.py`; omitting blank lines saves tokens over contiguous function blocks. A fresh excerpt-only review checked the grammar/constants, fractional rejection, success representation, parse-before-range precedence and range use against each requirement. No proposed program change was implemented, and this source review makes no compilation or runtime-correctness claim.
