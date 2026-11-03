# Task B selection: 44_luhn_checksum / Swift

## Common answer requirements

Explain leading-zero preservation of 0128469655154 as a digit string through validation/output; identify alternating doubled positions counting from the right; explain expected replacement of the rightmost check digit on failure.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The membership value is stored as text, including its leading0, and output uses that original text. Individual character-to-digit conversions create arithmetic values without converting/replacing the full string. Counting from the right with check digit at position1, double positions2,4,6,8,10,12; equivalently use odd zero-based reverse indices, or even length−i for a forward zero-based scan. Values above9 after doubling lose9. For this number, transformed digits from the right are 4,1,1,1,5,3,9,3,4,7,2,2,0, totaling42, so validation fails. Subtract the undoubled rightmost4 to get38; the nonnegative modulo-10 complement gives expected check digit2. Reporting keeps the original leading-zero string.



Source: `main.swift`. Selected original lines: 1,2,5,6,7,8,9,10,11,12,13,14,15,16,17. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `let numbers = [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    "688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `for number in numbers {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    let digits = number.utf8.map { Int($0) - 48 }` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    var sum = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    for (index, value) in digits.reversed().enumerated() {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        var digit = value` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        if index % 2 == 1 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            digit *= 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `            if digit > 9 { digit -= 9 }` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L14: `        sum += digit` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L16: `    let expected = (10 - (sum - digits.last!) % 10) % 10` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `    print(number + ": " + (sum % 10 == 0 ? "valid" : "invalid (expected check digit \(expected))"))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **329 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **354 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 321 tokens (versus 329); removes `let numbers = [`.
- Without L2: 238 tokens (versus 329); removes `"688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",`.
- Without L5: 319 tokens (versus 329); removes `for number in numbers {`.
- Without L6: 301 tokens (versus 329); removes `let digits = number.utf8.map { Int($0) - 48 }`.
- Without L7: 320 tokens (versus 329); removes `var sum = 0`.
- Without L8: 305 tokens (versus 329); removes `for (index, value) in digits.reversed().enumerated() {`.
- Without L9: 319 tokens (versus 329); removes `var digit = value`.
- Without L10: 313 tokens (versus 329); removes `if index % 2 == 1 {`.
- Without L11: 320 tokens (versus 329); removes `digit *= 2`.
- Without L12: 308 tokens (versus 329); removes `if digit > 9 { digit -= 9 }`.
- Without L13: 325 tokens (versus 329); removes `}`.
- Without L14: 321 tokens (versus 329); removes `sum += digit`.
- Without L15: 326 tokens (versus 329); removes `}`.
- Without L16: 294 tokens (versus 329); removes `let expected = (10 - (sum - digits.last!) % 10) % 10`.
- Without L17: 276 tokens (versus 329); removes `print(number + ": " + (sum % 10 == 0 ? "valid" : "invalid (expected check digit \(expected))"))`.
