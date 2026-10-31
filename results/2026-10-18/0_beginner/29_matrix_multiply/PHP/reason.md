# Task B selection: 29_matrix_multiply / PHP

## Common answer requirements

Obtain the first row of A and second column of B from source, identify all four multiplied pairs, compute their sum, and establish row-major output and the second five-character field of output line one.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Row 1 of A is (3,−2,5,1); column 2 of B is (4,2,−1,7). The products are 12,−4,−5,7 and their sum is 10. The row loop visits row one first and the column loop visits column one then column two; the inner four-element dot product therefore supplies 10 to the second width-five integer field before the row newline. That field is three spaces followed by 10. Matrix multiplication primitives have the same row-column dot-product semantics.



Source: `main.php`. Selected original lines: 3,4,5,6,7,8,9,10,11,12,13. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `$a = [[3, -2, 5, 1], [-4, 7, 0, 6], [2, 9, -8, -3]];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `$b = [[1, 4], [-5, 2], [6, -1], [0, 7]];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `for ($i = 0; $i < 3; $i++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    for ($j = 0; $j < 2; $j++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        $value = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        for ($k = 0; $k < 4; $k++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `            $value += $a[$i][$k] * $b[$k][$j];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L11: `        printf('%5d', $value);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L13: `    echo "\n";` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **246 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **253 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 195 tokens (versus 246); removes `$a = [[3, -2, 5, 1], [-4, 7, 0, 6], [2, 9, -8, -3]];`.
- Without L4: 207 tokens (versus 246); removes `$b = [[1, 4], [-5, 2], [6, -1], [0, 7]];`.
- Without L5: 220 tokens (versus 246); removes `for ($i = 0; $i < 3; $i++) {`.
- Without L6: 219 tokens (versus 246); removes `for ($j = 0; $j < 2; $j++) {`.
- Without L7: 236 tokens (versus 246); removes `$value = 0;`.
- Without L8: 218 tokens (versus 246); removes `for ($k = 0; $k < 4; $k++) {`.
- Without L9: 213 tokens (versus 246); removes `$value += $a[$i][$k] * $b[$k][$j];`.
- Without L10: 242 tokens (versus 246); removes `}`.
- Without L11: 230 tokens (versus 246); removes `printf('%5d', $value);`.
- Without L12: 243 tokens (versus 246); removes `}`.
- Without L13: 237 tokens (versus 246); removes `echo "\n";`.
