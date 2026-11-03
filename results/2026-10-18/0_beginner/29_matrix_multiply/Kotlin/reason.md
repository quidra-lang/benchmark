# Task B selection: 29_matrix_multiply / Kotlin

## Common answer requirements

Obtain the first row of A and second column of B from source, identify all four multiplied pairs, compute their sum, and establish row-major output and the second five-character field of output line one.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Row 1 of A is (3,−2,5,1); column 2 of B is (4,2,−1,7). The products are 12,−4,−5,7 and their sum is 10. The row loop visits row one first and the column loop visits column one then column two; the inner four-element dot product therefore supplies 10 to the second width-five integer field before the row newline. That field is three spaces followed by 10. Matrix multiplication primitives have the same row-column dot-product semantics.



Source: `main.kt`. Selected original lines: 2-6. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    val a = arrayOf(intArrayOf(3, -2, 5, 1), intArrayOf(-4, 7, 0, 6), intArrayOf(2, 9, -8, -3))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    val b = arrayOf(intArrayOf(1, 4), intArrayOf(-5, 2), intArrayOf(6, -1), intArrayOf(0, 7))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    for (i in 0 until 3) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        val row = (0 until 2).map { j -> (0 until 4).sumOf { k -> a[i][k] * b[k][j] } }` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        println(row.joinToString("") { it.toString().padStart(5) })` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **233 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **246 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 168 tokens (versus 233); removes `val a = arrayOf(intArrayOf(3, -2, 5, 1), intArrayOf(-4, 7, 0, 6), intArrayOf(2, 9, -8, -3))`.
- Without L3: 177 tokens (versus 233); removes `val b = arrayOf(intArrayOf(1, 4), intArrayOf(-5, 2), intArrayOf(6, -1), intArrayOf(0, 7))`.
- Without L4: 216 tokens (versus 233); removes `for (i in 0 until 3) {`.
- Without L5: 170 tokens (versus 233); removes `val row = (0 until 2).map { j -> (0 until 4).sumOf { k -> a[i][k] * b[k][j] } }`.
- Without L6: 201 tokens (versus 233); removes `println(row.joinToString("") { it.toString().padStart(5) })`.
