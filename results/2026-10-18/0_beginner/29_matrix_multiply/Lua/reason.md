# Task B selection: 29_matrix_multiply / Lua

## Common answer requirements

Obtain the first row of A and second column of B from source, identify all four multiplied pairs, compute their sum, and establish row-major output and the second five-character field of output line one.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Row 1 of A is (3,−2,5,1); column 2 of B is (4,2,−1,7). The products are 12,−4,−5,7 and their sum is 10. The row loop visits row one first and the column loop visits column one then column two; the inner four-element dot product therefore supplies 10 to the second width-five integer field before the row newline. That field is three spaces followed by 10. Matrix multiplication primitives have the same row-column dot-product semantics.



Source: `main.lua`. Selected original lines: 1,2,3,4,5,6,7,8,9. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `local a = {{3, -2, 5, 1}, {-4, 7, 0, 6}, {2, 9, -8, -3}}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `local b = {{1, 4}, {-5, 2}, {6, -1}, {0, 7}}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `for i = 1, 3 do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    for j = 1, 2 do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        local value = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        for k = 1, 4 do value = value + a[i][k] * b[k][j] end` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        io.write(string.format("%5d", value))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L9: `    io.write("\n")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **209 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **211 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 156 tokens (versus 209); removes `local a = {{3, -2, 5, 1}, {-4, 7, 0, 6}, {2, 9, -8, -3}}`.
- Without L2: 168 tokens (versus 209); removes `local b = {{1, 4}, {-5, 2}, {6, -1}, {0, 7}}`.
- Without L3: 196 tokens (versus 209); removes `for i = 1, 3 do`.
- Without L4: 195 tokens (versus 209); removes `for j = 1, 2 do`.
- Without L5: 199 tokens (versus 209); removes `local value = 0`.
- Without L6: 166 tokens (versus 209); removes `for k = 1, 4 do value = value + a[i][k] * b[k][j] end`.
- Without L7: 188 tokens (versus 209); removes `io.write(string.format("%5d", value))`.
- Without L8: 206 tokens (versus 209); removes `end`.
- Without L9: 198 tokens (versus 209); removes `io.write("\n")`.
