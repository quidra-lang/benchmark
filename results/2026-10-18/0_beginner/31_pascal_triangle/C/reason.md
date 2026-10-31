# Task B selection: 31_pascal_triangle / C

## Common answer requirements

Derive row 3 from the source initialization/recurrence as needed; trace row 4 endpoints and neighboring-value interior sums; identify exactly the space-separated row-4 output line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Starting at row 0 [1], the recurrence gives row 1 [1,1], row 2 [1,2,1], and row 3 [1,3,3,1]. The next endpoints are 1, with interiors 1+3=4, 3+3=6, 3+1=4. Thus row 4 prints `1 4 6 4 1` followed by a newline. Fresh-row implementations explicitly seed endpoints; zero-padding implementations get 0+1 and 1+0; right-to-left in-place updates use an unchanged left neighbor and an initially-zero new right slot, leaving the left endpoint at 1.



Source: `main.c`. Selected original lines: 4-10. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L4: `    int row[12] = {1};` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    for (int n = 0; n < 12; n++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        for (int k = n; k > 0; k--)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            row[k] += row[k - 1];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        for (int k = 0; k <= n; k++)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `            printf("%s%d", k ? " " : "", row[k]);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        putchar('\n');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **156 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **186 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L4: 140 tokens (versus 156); removes `int row[12] = {1};`.
- Without L5: 129 tokens (versus 156); removes `for (int n = 0; n < 12; n++) {`.
- Without L6: 131 tokens (versus 156); removes `for (int k = n; k > 0; k--)`.
- Without L7: 136 tokens (versus 156); removes `row[k] += row[k - 1];`.
- Without L8: 131 tokens (versus 156); removes `for (int k = 0; k <= n; k++)`.
- Without L9: 124 tokens (versus 156); removes `printf("%s%d", k ? " " : "", row[k]);`.
- Without L10: 145 tokens (versus 156); removes `putchar('\n');`.
