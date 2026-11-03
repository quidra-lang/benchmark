# Task B selection: 44_luhn_checksum / C

## Common answer requirements

Explain leading-zero preservation of 0128469655154 as a digit string through validation/output; identify alternating doubled positions counting from the right; explain expected replacement of the rightmost check digit on failure.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The membership value is stored as text, including its leading0, and output uses that original text. Individual character-to-digit conversions create arithmetic values without converting/replacing the full string. Counting from the right with check digit at position1, double positions2,4,6,8,10,12; equivalently use odd zero-based reverse indices, or even length−i for a forward zero-based scan. Values above9 after doubling lose9. For this number, transformed digits from the right are 4,1,1,1,5,3,9,3,4,7,2,2,0, totaling42, so validation fails. Subtract the undoubled rightmost4 to get38; the nonnegative modulo-10 complement gives expected check digit2. Reporting keeps the original leading-zero string.



Source: `main.c`. Selected original lines: 5,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L5: `    const char *numbers[] = {"688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        const char *s = numbers[k];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        int len = (int)strlen(s), sum = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        for (int i = 0; i < len; i++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            int d = s[len - 1 - i] - '0';` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `            if (i % 2) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `                d *= 2;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `                if (d > 9)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `                    d -= 9;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `            sum += d;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L19: `        if (sum % 10 == 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `            printf("%s: valid\n", s);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `        } else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L22: `            int expected = (10 - (sum - (s[len - 1] - '0')) % 10) % 10;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `            printf("%s: invalid (expected check digit %d)\n", s, expected);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **399 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **491 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L5: 297 tokens (versus 399); removes `const char *numbers[] = {"688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",`.
- Without L8: 382 tokens (versus 399); removes `const char *s = numbers[k];`.
- Without L9: 375 tokens (versus 399); removes `int len = (int)strlen(s), sum = 0;`.
- Without L10: 372 tokens (versus 399); removes `for (int i = 0; i < len; i++) {`.
- Without L11: 370 tokens (versus 399); removes `int d = s[len - 1 - i] - '0';`.
- Without L12: 384 tokens (versus 399); removes `if (i % 2) {`.
- Without L13: 388 tokens (versus 399); removes `d *= 2;`.
- Without L14: 385 tokens (versus 399); removes `if (d > 9)`.
- Without L15: 387 tokens (versus 399); removes `d -= 9;`.
- Without L16: 394 tokens (versus 399); removes `}`.
- Without L17: 389 tokens (versus 399); removes `sum += d;`.
- Without L18: 395 tokens (versus 399); removes `}`.
- Without L19: 380 tokens (versus 399); removes `if (sum % 10 == 0) {`.
- Without L20: 380 tokens (versus 399); removes `printf("%s: valid\n", s);`.
- Without L21: 391 tokens (versus 399); removes `} else {`.
- Without L22: 349 tokens (versus 399); removes `int expected = (10 - (sum - (s[len - 1] - '0')) % 10) % 10;`.
- Without L23: 366 tokens (versus 399); removes `printf("%s: invalid (expected check digit %d)\n", s, expected);`.
