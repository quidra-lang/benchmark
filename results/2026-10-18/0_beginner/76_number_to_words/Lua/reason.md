# Task B source selection

## Common answer requirements

Trace 0, 71000 and 300019. Distinguish whole-input zero from zero remainders; identify thousand/hundred/smaller conversion and joining, and explain missing zero components and spacing.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The whole input 0 prints zero via a dedicated zero case or an empty-parts fallback. 71000 splits into 71 thousands and zero remainder, giving seventy-one thousand; the zero remainder is omitted. 300019 splits into 300 thousands and 19, giving three hundred thousand nineteen. Inside the small-number converter 300 contributes three hundred and no zero remainder. Parts are appended only when nonempty and joined with one separator, or spaces are conditionally emitted only when both adjacent components exist. Hyphens join tens and units, so they do not add stray spaces.



## Source evidence and dependencies

The selected locations in `main.lua` are L1, L2, L3, L5, L7, L8, L9, L10, L11, L12, L13, L14, L15, L16, L18, L21, L22, L23, L24, L25, L26, L27. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `local units = {`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L2: `"zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L3: `"twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L5: `local tens = {"zero", "ten", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"}`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L7: `local function small_words(number)`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L8: `local parts = {}`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L9: `local hundreds, remainder = number // 100, number % 100`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L10: `if hundreds > 0 then parts[#parts + 1] = units[hundreds + 1] .. " hundred" end`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L11: `if remainder >= 20 then`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L12: `local phrase = tens[remainder // 10 + 1]`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L13: `if remainder % 10 > 0 then phrase = phrase .. "-" .. units[remainder % 10 + 1] end`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L14: `parts[#parts + 1] = phrase`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L15: `elseif remainder > 0 then`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L16: `parts[#parts + 1] = units[remainder + 1]`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L18: `return table.concat(parts, " ")`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L21: `local function number_words(number)`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L22: `if number == 0 then return "zero" end`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L23: `local parts = {}`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L24: `local thousands, remainder = number // 1000, number % 1000`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L25: `if thousands > 0 then parts[#parts + 1] = small_words(thousands) .. " thousand" end`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L26: `if remainder > 0 then parts[#parts + 1] = small_words(remainder) end`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L27: `return table.concat(parts, " ")`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **562 tokens** for the final selected lines. The prior candidate measured 557 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.

Final original source lines: L1, L2, L3, L5, L7, L8, L9, L10, L11, L12, L13, L14, L15, L16, L17, L18, L19, L21, L22, L23, L24, L25, L26, L27.
- L17: `    end` — Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.
- L19: `end` — Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.

Final selection: 562 metric tokens; contiguous span L1–L27: 566 tokens; complete source: 662 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
