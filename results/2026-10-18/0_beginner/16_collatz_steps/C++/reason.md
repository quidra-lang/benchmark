# Task B selection: 16_collatz_steps / C++

## Common answer requirements

Compare start1 and6: initialization of maximum and zero steps; termination before any operation for1; trace every transformation for6 and derive step count/peak while distinguishing inclusion of start from performed operations.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

For start1, n already equals1, so the loop body executes zero times: steps remains0 and maximum remains its initialized starting value1. For6 the states are6→3→10→5→16→8→4→2→1, eight transformations with maximum16. Initial maximum=start includes6 before any operation; the counter starts0 and increments only after transforming n. Each updated state can raise the running maximum; the starting state never adds a step merely by being included.



Source: `main.cpp`. Selected original lines: 6-11. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L6: `    for (long long start : std::array<long long, 5>{1, 6, 27, 97, 871}) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        long long n = start, m = n, k = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        while (n != 1) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `            n = n % 2 == 0 ? n / 2 : 3 * n + 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `            ++k;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            m = std::max(m, n);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **150 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **232 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L6: 104 tokens (versus 150); removes `for (long long start : std::array<long long, 5>{1, 6, 27, 97, 871}) {`.
- Without L7: 123 tokens (versus 150); removes `long long n = start, m = n, k = 0;`.
- Without L8: 136 tokens (versus 150); removes `while (n != 1) {`.
- Without L9: 112 tokens (versus 150); removes `n = n % 2 == 0 ? n / 2 : 3 * n + 1;`.
- Without L10: 143 tokens (versus 150); removes `++k;`.
- Without L11: 132 tokens (versus 150); removes `m = std::max(m, n);`.
