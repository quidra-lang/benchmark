# Task B selection: 44_luhn_checksum / Kotlin

## Common answer requirements

Explain leading-zero preservation of 0128469655154 as a digit string through validation/output; identify alternating doubled positions counting from the right; explain expected replacement of the rightmost check digit on failure.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The membership value is stored as text, including its leading0, and output uses that original text. Individual character-to-digit conversions create arithmetic values without converting/replacing the full string. Counting from the right with check digit at position1, double positions2,4,6,8,10,12; equivalently use odd zero-based reverse indices, or even length−i for a forward zero-based scan. Values above9 after doubling lose9. For this number, transformed digits from the right are 4,1,1,1,5,3,9,3,4,7,2,2,0, totaling42, so validation fails. Subtract the undoubled rightmost4 to get38; the nonnegative modulo-10 complement gives expected check digit2. Reporting keeps the original leading-zero string.



Source: `main.kt`. Selected original lines: 2,3,6,7,8,9,10,11,12,13,14,15,16,17. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    val numbers = listOf(` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `        "688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    for (number in numbers) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        var sum = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        for ((index, ch) in number.reversed().withIndex()) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `            var digit = ch - '0'` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `            if (index % 2 == 1) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `                digit *= 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `                if (digit > 9) digit -= 9` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L14: `            sum += digit` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L16: `        val expected = (10 - (sum - (number.last() - '0')) % 10) % 10` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `        println(number + ": " + if (sum % 10 == 0) "valid" else "invalid (expected check digit $expected)")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **335 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **373 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 324 tokens (versus 335); removes `val numbers = listOf(`.
- Without L3: 243 tokens (versus 335); removes `"688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",`.
- Without L6: 322 tokens (versus 335); removes `for (number in numbers) {`.
- Without L7: 325 tokens (versus 335); removes `var sum = 0`.
- Without L8: 307 tokens (versus 335); removes `for ((index, ch) in number.reversed().withIndex()) {`.
- Without L9: 318 tokens (versus 335); removes `var digit = ch - '0'`.
- Without L10: 316 tokens (versus 335); removes `if (index % 2 == 1) {`.
- Without L11: 325 tokens (versus 335); removes `digit *= 2`.
- Without L12: 315 tokens (versus 335); removes `if (digit > 9) digit -= 9`.
- Without L13: 330 tokens (versus 335); removes `}`.
- Without L14: 326 tokens (versus 335); removes `sum += digit`.
- Without L15: 331 tokens (versus 335); removes `}`.
- Without L16: 290 tokens (versus 335); removes `val expected = (10 - (sum - (number.last() - '0')) % 10) % 10`.
- Without L17: 283 tokens (versus 335); removes `println(number + ": " + if (sum % 10 == 0) "valid" else "invalid (expected check digit $expected)")`.
