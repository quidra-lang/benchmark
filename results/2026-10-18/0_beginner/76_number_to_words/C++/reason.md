# Task B source selection

## Common answer requirements

Trace 0, 71000 and 300019. Distinguish whole-input zero from zero remainders; identify thousand/hundred/smaller conversion and joining, and explain missing zero components and spacing.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The whole input 0 prints zero via a dedicated zero case or an empty-parts fallback. 71000 splits into 71 thousands and zero remainder, giving seventy-one thousand; the zero remainder is omitted. 300019 splits into 300 thousands and 19, giving three hundred thousand nineteen. Inside the small-number converter 300 contributes three hundred and no zero remainder. Parts are appended only when nonempty and joined with one separator, or spaces are conditionally emitted only when both adjacent components exist. Hyphens join tens and units, so they do not add stray spaces.



## Source evidence and dependencies

The selected locations in `main.cpp` are L5, L6, L7, L8, L9, L11, L12, L13, L14, L15, L16, L17, L19, L20, L21, L22, L23, L24, L26, L31, L32, L33, L34, L35, L36, L37, L38, L39. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L5: `const std::array<std::string, 20> small = {"zero", "one", "two", "three", "four", "five", "six",`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L6: `"seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L7: `"seventeen", "eighteen", "nineteen"};`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L8: `const std::array<std::string, 10> tens = {"", "", "twenty", "thirty", "forty", "fifty", "sixty",`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L9: `"seventy", "eighty", "ninety"};`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L11: `std::string under(int n) {`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L12: `std::string out;`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L13: `if (n >= 100) {`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L14: `out = small[n / 100] + " hundred";`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L15: `n %= 100;`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L16: `if (n)`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L17: `out += ' ';`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L19: `if (n >= 20) {`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L20: `out += tens[n / 10];`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L21: `if (n % 10)`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L22: `out += "-" + small[n % 10];`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L23: `} else if (n) {`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L24: `out += small[n];`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L26: `return out;`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L31: `std::string result;`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L32: `if (n == 0)`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L33: `result = "zero";`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L34: `if (n >= 1000)`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L35: `result = under(n / 1000) + " thousand";`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L36: `if (n % 1000) {`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L37: `if (!result.empty())`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L38: `result += ' ';`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L39: `result += under(n % 1000);`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **531 tokens** for the final selected lines. The prior candidate measured 523 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.

Final original source lines: L5, L6, L7, L8, L9, L11, L12, L13, L14, L15, L16, L17, L18, L19, L20, L21, L22, L23, L24, L25, L26, L27, L31, L32, L33, L34, L35, L36, L37, L38, L39.
- L18: `    }` — Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.
- L25: `    }` — Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.
- L27: `}` — Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.

Final selection: 531 metric tokens; contiguous span L5–L39: 608 tokens; complete source: 668 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
