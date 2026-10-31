# Task B selection: 37_bubble_sort_passes / C#

## Common answer requirements

Trace the first-pass comparisons involving 88 using the input and swap semantics; identify its positions and final placement; derive the second-pass bound excluding that position; distinguish comparisons from the conditional total-swap counter.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Initially 88 is at zero-based position 3 (one-based 4). At first-pass j=2, 64 is compared with 88 and no swap occurs. Then 88 swaps with 41,5,72,36 at successive comparisons, occupying positions 4,5,6,7. It is the largest value, so every comparison to its right neighbor swaps it rightward. Pass one compares j=0..6; pass two only j=0..5, so final position 7 is excluded. In one-based implementations these are adjacent pairs ending at positions 8 then 7. There are seven adjacent comparisons on pass one, five swaps overall on that pass (the earlier 64/13 swap plus four involving 88), and only conditional swaps increment the counter; a comparison by itself is not counted as a swap.



Source: `Program.cs`. Selected original lines: 6,7,8,11,12,13,14,15,17,18,19. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L6: `int[] values = { 27, 64, 13, 88, 41, 5, 72, 36 };` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `int swaps = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `for (int p = 1; p <= 7; p++)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    for (int j = 0; j <= 7 - p; j++)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `    {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L13: `        if (values[j] > values[j + 1])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `            (values[j], values[j + 1]) = (values[j + 1], values[j]);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `            swaps++;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L19: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.

## Minimization and semantics

The selected excerpt measures **185 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **297 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L6: 143 tokens (versus 185); removes `int[] values = { 27, 64, 13, 88, 41, 5, 72, 36 };`.
- Without L7: 176 tokens (versus 185); removes `int swaps = 0;`.
- Without L8: 162 tokens (versus 185); removes `for (int p = 1; p <= 7; p++)`.
- Without L11: 157 tokens (versus 185); removes `for (int j = 0; j <= 7 - p; j++)`.
- Without L12: 182 tokens (versus 185); removes `{`.
- Without L13: 163 tokens (versus 185); removes `if (values[j] > values[j + 1])`.
- Without L14: 181 tokens (versus 185); removes `{`.
- Without L15: 145 tokens (versus 185); removes `(values[j], values[j + 1]) = (values[j + 1], values[j]);`.
- Without L17: 178 tokens (versus 185); removes `swaps++;`.
- Without L18: 181 tokens (versus 185); removes `}`.
- Without L19: 182 tokens (versus 185); removes `}`.
