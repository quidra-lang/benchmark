# Task B source selection

## Common answer requirements

Trace 0, 71000 and 300019. Distinguish whole-input zero from zero remainders; identify thousand/hundred/smaller conversion and joining, and explain missing zero components and spacing.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The whole input 0 prints zero via a dedicated zero case or an empty-parts fallback. 71000 splits into 71 thousands and zero remainder, giving seventy-one thousand; the zero remainder is omitted. 300019 splits into 300 thousands and 19, giving three hundred thousand nineteen. Inside the small-number converter 300 contributes three hundred and no zero remainder. Parts are appended only when nonempty and joined with one separator, or spaces are conditionally emitted only when both adjacent components exist. Hyphens join tens and units, so they do not add stray spaces.



## Source evidence and dependencies

The selected locations in `main.qui` are L1, L2, L3, L4, L5, L7, L8, L9, L10, L11, L12, L13, L14, L15, L16, L17, L18, L19, L23, L24, L25, L26, L27, L28, L29, L30. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `string under_thousand(int number)`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L2: `string[] small = [`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L3: `"zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L4: `"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L5: `"nineteen",`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L7: `string[] tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L8: `string[] parts = []`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L9: `if number >= 100`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L10: `parts = parts.append(small[number / 100] + " hundred")`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L11: `int remainder = number % 100`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L12: `if remainder >= 20`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L13: `string part = tens[remainder / 10]`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L14: `if remainder % 10 != 0`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L15: `part += "-" + small[remainder % 10]`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L16: `parts = parts.append(part)`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L17: `elif remainder > 0`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L18: `parts = parts.append(small[remainder])`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L19: `return parts.join(" ")`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L23: `string[] parts = []`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L24: `if number == 0`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L25: `parts = parts.append("zero")`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L26: `if number >= 1000`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L27: `parts = parts.append(under_thousand(number / 1000) + " thousand")`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L28: `if number % 1000 > 0`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L29: `parts = parts.append(under_thousand(number % 1000))`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L30: `print("{number}: {parts.join(" ")}{NL}")`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py`'s `tokenize` reports **508 tokens** for the selected original complete lines. A contiguous-context alternative spanning L1–L30 costs **575 tokens**; the entire source costs **575 tokens**. The selected set plus the additional context line L6 costs **511 tokens**. That extra line does not add an answer requirement. These comparisons favor the retained dependency slice over context-heavy alternatives. Every selected substantive line was reviewed for the facts or dependency it contributes. This is a minimized sufficient selection among reviewed alternatives, not a proof of a global mathematical minimum.
