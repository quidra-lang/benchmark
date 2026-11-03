# Task B selection: 37_bubble_sort_passes / TypeScript

## Common answer requirements

Trace the first-pass comparisons involving 88 using the input and swap semantics; identify its positions and final placement; derive the second-pass bound excluding that position; distinguish comparisons from the conditional total-swap counter.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Initially 88 is at zero-based position 3 (one-based 4). At first-pass j=2, 64 is compared with 88 and no swap occurs. Then 88 swaps with 41,5,72,36 at successive comparisons, occupying positions 4,5,6,7. It is the largest value, so every comparison to its right neighbor swaps it rightward. Pass one compares j=0..6; pass two only j=0..5, so final position 7 is excluded. In one-based implementations these are adjacent pairs ending at positions 8 then 7. There are seven adjacent comparisons on pass one, five swaps overall on that pass (the earlier 64/13 swap plus four involving 88), and only conditional swaps increment the counter; a comparison by itself is not counted as a swap.



Source: `main.ts`. Selected original lines: 1-3,5-8. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `const values = [27, 64, 13, 88, 41, 5, 72, 36];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `let swaps = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `for (let p = 1; p < values.length; p++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `  for (let j = 0; j < values.length - p; j++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    if (values[j] > values[j + 1]) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `      [values[j], values[j + 1]] = [values[j + 1], values[j]];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `      swaps++;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **173 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **255 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 134 tokens (versus 173); removes `const values = [27, 64, 13, 88, 41, 5, 72, 36];`.
- Without L2: 164 tokens (versus 173); removes `let swaps = 0;`.
- Without L3: 146 tokens (versus 173); removes `for (let p = 1; p < values.length; p++) {`.
- Without L5: 141 tokens (versus 173); removes `for (let j = 0; j < values.length - p; j++) {`.
- Without L6: 150 tokens (versus 173); removes `if (values[j] > values[j + 1]) {`.
- Without L7: 136 tokens (versus 173); removes `[values[j], values[j + 1]] = [values[j + 1], values[j]];`.
- Without L8: 167 tokens (versus 173); removes `swaps++;`.
