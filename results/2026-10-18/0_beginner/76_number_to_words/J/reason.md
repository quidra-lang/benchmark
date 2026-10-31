# Task B source selection

## Common answer requirements

Trace 0, 71000 and 300019. Distinguish whole-input zero from zero remainders; identify thousand/hundred/smaller conversion and joining, and explain missing zero components and spacing.

These answer requirements are identical for all twenty languages. The Task B assumptions apply; this is source analysis, not execution or verification of Task A.

## Supported answer and change analysis

The whole input 0 prints zero via a dedicated zero case or an empty-parts fallback. 71000 splits into 71 thousands and zero remainder, giving seventy-one thousand; the zero remainder is omitted. 300019 splits into 300 thousands and 19, giving three hundred thousand nineteen. Inside the small-number converter 300 contributes three hundred and no zero remainder. Parts are appended only when nonempty and joined with one separator, or spaces are conditionally emitted only when both adjacent components exist. Hyphens join tens and units, so they do not add stray spaces.



## Source evidence and dependencies

The selected locations in `main.ijs` are L1, L2, L3, L4, L5, L6, L7, L8, L9, L10, L11, L13, L17, L18, L19, L20, L21. Each retained line below supplies the indicated operation, condition, declaration, data value, or enclosing branch needed to connect the answer to this implementation:

- L1: `underthousand =: 3 : 0`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L2: `small =. ;:'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L3: `tens =. ;:'zero zero twenty thirty forty fifty sixty seventy eighty ninety'`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L4: `parts =. 0$<''`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L5: `if. y>:100 do. parts =. parts,< (>(<.y%100){small),' hundred' end.`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L6: `remainder =. 100|y`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L7: `if. remainder>:20 do.`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L8: `part =. >(<.remainder%10){tens`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L9: `if. 0~:10|remainder do. part =. part,'-',>(10|remainder){small end.`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L10: `parts =. parts,<part`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L11: `elseif. remainder>0 do. parts =. parts,remainder{small`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L13: `}. ; (<' ') ,&.> parts`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L17: `parts =. 0$<''`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L18: `if. number=0 do. parts =. <'zero' end.`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L19: `if. number>:1000 do. parts =. parts,< (underthousand <.number%1000),' thousand' end.`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L20: `if. 0~:1000|number do. parts =. parts,<underthousand 1000|number end.`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.
- L21: `smoutput (":number),': ',}. ; (<' ') ,&.> parts`. This line supplies a number-word table/index, conversion branch, nonzero remainder guard, component accumulator or separator operation used by the three requested traces. It distinguishes entire zero from absent inner components.

## Language semantics and minimization

Use the language's ordinary expression evaluation, indexing, comparison, assignment, iteration and control-flow semantics, and the documented semantics of the standard-library operations shown in the excerpt. User-defined behavior needed for the answer is included rather than inferred solely from a helper name. Source lines need not form a standalone compilable program. Unrelated input/output setup, imports, whitespace, and purely structural closing lines are omitted unless they occur on a necessary complete line. The analysis identifies the affected logic; no replacement program is supplied.

`metric/tokenizer.py` `tokenize` reports **393 tokens** for the final selected lines. The prior candidate measured 388 tokens. The final selection includes the required scope/data association identified by independent excerpt review; no Task A program was run.

## Independent excerpt review repair

Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.

Final original source lines: L1, L2, L3, L4, L5, L6, L7, L8, L9, L10, L11, L12, L13, L14, L17, L18, L19, L20, L21.
- L12: `  end.` — Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.
- L14: `)` — Close conditional assembly regions before returning/joining parts, and separate whole-input zero, thousand and remainder handling. A zero partial remainder therefore does not gate or include the completed nonempty phrase.

Final selection: 393 metric tokens; contiguous span L1–L21: 447 tokens; complete source: 457 tokens. Scope-only lines are retained where they distinguish relevant branch/loop timing.
