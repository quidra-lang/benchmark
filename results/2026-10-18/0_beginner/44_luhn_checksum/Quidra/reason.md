# Task B selection: 44_luhn_checksum / Quidra

## Common answer requirements

Explain leading-zero preservation of 0128469655154 as a digit string through validation/output; identify alternating doubled positions counting from the right; explain expected replacement of the rightmost check digit on failure.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The membership value is stored as text, including its leading0, and output uses that original text. Individual character-to-digit conversions create arithmetic values without converting/replacing the full string. Counting from the right with check digit at position1, double positions2,4,6,8,10,12; equivalently use odd zero-based reverse indices, or even length−i for a forward zero-based scan. Values above9 after doubling lose9. For this number, transformed digits from the right are 4,1,1,1,5,3,9,3,4,7,2,2,0, totaling42, so validation fails. Subtract the undoubled rightmost4 to get38; the nonnegative modulo-10 complement gives expected check digit2. Reporting keeps the original leading-zero string.



Source: `main.qui`. Selected original lines: 1-2,5-19. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `string[] numbers = [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    "688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `for string number = numbers[]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    int total = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    for 0 <= int i < int(len(number))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        int digit = int.parse(number[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        if (int(len(number)) - i) % 2 == 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `            digit *= 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            if digit > 9` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `                digit -= 9` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        total += digit` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    if total % 10 == 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `        print("{number}: valid{NL}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `    else` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `        int last = int.parse(number[len(number) - 1])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        int expected = (10 - (total - last) % 10) % 10` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `        print("{number}: invalid (expected check digit {expected}){NL}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **342 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **365 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 333 tokens (versus 342); removes `string[] numbers = [`.
- Without L2: 251 tokens (versus 342); removes `"688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",`.
- Without L5: 331 tokens (versus 342); removes `for string number = numbers[]`.
- Without L6: 333 tokens (versus 342); removes `int total = 0`.
- Without L7: 321 tokens (versus 342); removes `for 0 <= int i < int(len(number))`.
- Without L8: 324 tokens (versus 342); removes `int digit = int.parse(number[i])`.
- Without L9: 316 tokens (versus 342); removes `if (int(len(number)) - i) % 2 == 0`.
- Without L10: 333 tokens (versus 342); removes `digit *= 2`.
- Without L11: 331 tokens (versus 342); removes `if digit > 9`.
- Without L12: 332 tokens (versus 342); removes `digit -= 9`.
- Without L13: 334 tokens (versus 342); removes `total += digit`.
- Without L14: 328 tokens (versus 342); removes `if total % 10 == 0`.
- Without L15: 326 tokens (versus 342); removes `print("{number}: valid{NL}")`.
- Without L16: 339 tokens (versus 342); removes `else`.
- Without L17: 317 tokens (versus 342); removes `int last = int.parse(number[len(number) - 1])`.
- Without L18: 309 tokens (versus 342); removes `int expected = (10 - (total - last) % 10) % 10`.
- Without L19: 314 tokens (versus 342); removes `print("{number}: invalid (expected check digit {expected}){NL}")`.
