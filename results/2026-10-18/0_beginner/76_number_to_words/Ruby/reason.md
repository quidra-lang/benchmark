# Task B source selection

## Common answer requirements

Trace 0, 71000 and 300019. Distinguish whole-input zero from zero remainders; identify thousand/hundred/smaller conversion and joining, and explain missing zero components and spacing.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The whole input 0 prints zero via a dedicated zero case or an empty-parts fallback. 71000 splits into 71 thousands and zero remainder, giving seventy-one thousand; the zero remainder is omitted. 300019 splits into 300 thousands and 19, giving three hundred thousand nineteen. Inside the small-number converter 300 contributes three hundred and no zero remainder. Parts are appended only when nonempty and joined with one separator, or spaces are conditionally emitted only when both adjacent components exist. Hyphens join tens and units, so they do not add stray spaces.



## Source evidence and dependencies

The selected locations in `main.rb` are L1, L2, L3, L5, L7, L8, L9, L10, L11, L12, L13, L14, L15, L16, L18, L22, L23, L24, L25. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `SMALL = %w[`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L2: `zero one two three four five six seven eight nine`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L3: `ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L5: `TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety']`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L7: `def under_thousand(value)`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L8: `parts = []`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L9: `parts << SMALL[value / 100] + ' hundred' if value >= 100`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L10: `remainder = value % 100`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L11: `if remainder >= 20`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L12: `word = TENS[remainder / 10]`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L13: `word += '-' + SMALL[remainder % 10] unless (remainder % 10).zero?`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L14: `parts << word`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L15: `elsif remainder.positive?`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L16: `parts << SMALL[remainder]`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L18: `parts.join(' ')`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L22: `parts = []`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L23: `parts << under_thousand(number / 1000) + ' thousand' if number >= 1000`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L24: `parts << under_thousand(number % 1000) unless (number % 1000).zero?`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L25: `words = parts.empty? ? SMALL[0] : parts.join(' ')`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **372 tokens** for the final selected lines. The prior candidate measured 367 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.

Final original source lines: L1, L2, L3, L5, L7, L8, L9, L10, L11, L12, L13, L14, L15, L16, L17, L18, L19, L22, L23, L24, L25.
- L17: `  end` — Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.
- L19: `end` — Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.

Final selection: 372 metric tokens; contiguous span L1–L25: 427 tokens; complete source: 444 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
