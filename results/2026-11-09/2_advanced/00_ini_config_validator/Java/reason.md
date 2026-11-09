# Task B — schema size normalization

The same answer requirements apply in every language: identify the size spelling grammar and case-insensitive binary unit scale; follow exact decimal-to-byte arithmetic and its failure exit; trace 1.5MB and 0.05KB; identify the successful source value representation and the normalization/error boundary; show how optional range bounds consume that successful numeric value, in order. Includes, inheritance, interpolation implementation and other scalar types are outside this routine-level question.

## Java source evidence

The size case of Main.scalar uses Pattern.matches semantics, an explicit factor map and long arithmetic, then Value.number(kind,value). The record and its number factory establish a primitive long byte field, while null is the parse-failure result. normalize throws typeError/E_TYPE before checkRange; range consumes value.number and reparses nonempty size bounds through Main.scalar, rejecting strictly less/greater endpoints. The selected number helper is needed because it is user code, rather than assuming its name implements decimal conversion.

For 1.5MB the whole part contributes 1×1048576 and the fractional part contributes (5×1048576)/10 = 524288 exactly, giving 1572864 integer bytes. For 0.05KB the fractional numerator is 5×1024 = 5120 with divisor 100; the nonzero remainder rejects the value before any range comparison. This becomes E_TYPE, not a rounded 51-byte value. A successful value is checked against any nonempty size bounds in the same byte unit; strict less-than/greater-than rejection makes equality acceptable. Without a range failure it crosses the normalization return boundary; the first failed parse or range check stops that operation.

## Necessity and alternatives

- `Main.java`: 19, 21, 35, 38, 47, 53, 55, 56, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 326, 327, 328, 329, 330, 331, 332, 333, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378

The parser body is required because a name or return type alone cannot establish exact-byte divisibility, accepted spellings or unit factors. The selected dispatch, failure/return and range-consumer lines connect that computation to the requested operation. Type/standard-library conversion guarantees are used instead of copying their implementations; custom helpers needed to establish the grammar or arithmetic are retained. Whole scalar dispatches, list/string/date algorithms, callers that only carry an already expanded string, include processing and inheritance were considered and excluded because they add no evidence for these answer requirements. Diagnostic escaping/rendering internals are unnecessary to identify the first diagnostic code and precedence, so no exact escaped diagnostic text is claimed.

The excerpt has 1549 tokens under `metric/tokenizer.py`; omitting blank lines saves tokens over contiguous function blocks. A fresh excerpt-only review checked the grammar/constants, fractional rejection, success representation, parse-before-range precedence and range use against each requirement. No proposed program change was implemented, and this source review makes no compilation or runtime-correctness claim.
