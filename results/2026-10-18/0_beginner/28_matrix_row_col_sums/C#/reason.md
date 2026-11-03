# Task B selection: 28_matrix_row_col_sums / C#

## Common answer requirements

Locate all row, column, and overall sum computations and any shared helper/callers that must become maxima; explain appropriate initialization and aggregation; retain row elements, six-character fields, and five-line arrangement.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Change each row reduction from addition to maximum; change each column accumulator/reduction similarly; replace the grand-total sum with the maximum of row or column maxima (equivalently all matrix elements). For explicit accumulators, seed a maximum from an actual first element or a suitable minimum sentinel rather than relying on additive zero as a general identity. A shared sum helper can become a maximum reduction if every shown call needs maxima; preserve its existing field formatting and row/column output positions. Output operations containing the affected aggregate identify its destination; unchanged element printing and input literals need no edits.



Source: `Program.cs`. Selected original lines: 14,17,21,23,26. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L14: `int[] columns = new int[5];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `    int sum = row.Sum();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `        columns[j] += row[j];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `    Console.WriteLine($"{sum,6}");` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L26: `Console.WriteLine($"{columns.Sum(),6}");` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **81 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **332 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L14: 66 tokens (versus 81); removes `int[] columns = new int[5];`.
- Without L17: 67 tokens (versus 81); removes `int sum = row.Sum();`.
- Without L21: 66 tokens (versus 81); removes `columns[j] += row[j];`.
- Without L23: 64 tokens (versus 81); removes `Console.WriteLine($"{sum,6}");`.
- Without L26: 61 tokens (versus 81); removes `Console.WriteLine($"{columns.Sum(),6}");`.
