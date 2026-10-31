# Task B selection: 37_bubble_sort_passes / Julia

## Common answer requirements

Trace the first-pass comparisons involving 88 using the input and swap semantics; identify its positions and final placement; derive the second-pass bound excluding that position; distinguish comparisons from the conditional total-swap counter.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Initially 88 is at zero-based position 3 (one-based 4). At first-pass j=2, 64 is compared with 88 and no swap occurs. Then 88 swaps with 41,5,72,36 at successive comparisons, occupying positions 4,5,6,7. It is the largest value, so every comparison to its right neighbor swaps it rightward. Pass one compares j=0..6; pass two only j=0..5, so final position 7 is excluded. In one-based implementations these are adjacent pairs ending at positions 8 then 7. There are seven adjacent comparisons on pass one, five swaps overall on that pass (the earlier 64/13 swap plus four involving 88), and only conditional swaps increment the counter; a comparison by itself is not counted as a swap.



Source: `main.jl`. Selected original lines: 2-4,6-9. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    numbers = [27, 64, 13, 88, 41, 5, 72, 36]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    total = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    for pass = 1:7` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        for j = 1:(8-pass)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            if numbers[j] > numbers[j+1]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `                numbers[j], numbers[j+1] = numbers[j+1], numbers[j]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `                total += 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **132 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **227 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 95 tokens (versus 132); removes `numbers = [27, 64, 13, 88, 41, 5, 72, 36]`.
- Without L3: 125 tokens (versus 132); removes `total = 0`.
- Without L4: 121 tokens (versus 132); removes `for pass = 1:7`.
- Without L6: 116 tokens (versus 132); removes `for j = 1:(8-pass)`.
- Without L7: 113 tokens (versus 132); removes `if numbers[j] > numbers[j+1]`.
- Without L8: 100 tokens (versus 132); removes `numbers[j], numbers[j+1] = numbers[j+1], numbers[j]`.
- Without L9: 122 tokens (versus 132); removes `total += 1`.
