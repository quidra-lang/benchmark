# Task B selection: 16_collatz_steps / Go

## Common answer requirements

Compare start1 and6: initialization of maximum and zero steps; termination before any operation for1; trace every transformation for6 and derive step count/peak while distinguishing inclusion of start from performed operations.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

For start1, n already equals1, so the loop body executes zero times: steps remains0 and maximum remains its initialized starting value1. For6 the states are6→3→10→5→16→8→4→2→1, eight transformations with maximum16. Initial maximum=start includes6 before any operation; the counter starts0 and increments only after transforming n. Each updated state can raise the running maximum; the starting state never adds a step merely by being included.

The two branches update n, and the common counter/max updates occur afterward. Their scope is part of the selected control-flow evidence.

Source: `main.go`. Selected original lines: 6,7,8,9,10,11,12,13,14,15. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L6: `	for _, start := range []int64{1, 6, 27, 97, 871} {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `		n, m, k := start, start, 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `		for n != 1 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `			if n%2 == 0 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `				n /= 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `			} else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L12: `				n = 3*n + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `			}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L14: `			k++` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `			m = max(m, n)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **144 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **206 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L6: 108 tokens (versus 144); removes `for _, start := range []int64{1, 6, 27, 97, 871} {`.
- Without L7: 124 tokens (versus 144); removes `n, m, k := start, start, 0`.
- Without L8: 132 tokens (versus 144); removes `for n != 1 {`.
- Without L9: 129 tokens (versus 144); removes `if n%2 == 0 {`.
- Without L10: 134 tokens (versus 144); removes `n /= 2`.
- Without L11: 135 tokens (versus 144); removes `} else {`.
- Without L12: 128 tokens (versus 144); removes `n = 3*n + 1`.
- Without L13: 139 tokens (versus 144); removes `}`.
- Without L14: 138 tokens (versus 144); removes `k++`.
- Without L15: 129 tokens (versus 144); removes `m = max(m, n)`.
