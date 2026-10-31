# Task B selection: 44_luhn_checksum / Lua

## Common answer requirements

Explain leading-zero preservation of 0128469655154 as a digit string through validation/output; identify alternating doubled positions counting from the right; explain expected replacement of the rightmost check digit on failure.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The membership value is stored as text, including its leading0, and output uses that original text. Individual character-to-digit conversions create arithmetic values without converting/replacing the full string. Counting from the right with check digit at position1, double positions2,4,6,8,10,12; equivalently use odd zero-based reverse indices, or even length−i for a forward zero-based scan. Values above9 after doubling lose9. For this number, transformed digits from the right are 4,1,1,1,5,3,9,3,4,7,2,2,0, totaling42, so validation fails. Subtract the undoubled rightmost4 to get38; the nonnegative modulo-10 complement gives expected check digit2. Reporting keeps the original leading-zero string.



Source: `main.lua`. Selected original lines: 1,2,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `local numbers = {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    "688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `for _, number in ipairs(numbers) do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    local total = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    for position = 1, #number do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        local digit = tonumber(number:sub(#number - position + 1, #number - position + 1))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        if position % 2 == 0 then` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `            digit = digit * 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            if digit > 9 then digit = digit - 9 end` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L13: `        total = total + digit` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `    if total % 10 == 0 then` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `        io.write(number, ": valid\n")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `    else` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        local expected = (-(total - tonumber(number:sub(-1)))) % 10` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `        io.write(string.format("%s: invalid (expected check digit %d)\n", number, expected))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **359 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **387 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 351 tokens (versus 359); removes `local numbers = {`.
- Without L2: 268 tokens (versus 359); removes `"688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",`.
- Without L5: 343 tokens (versus 359); removes `for _, number in ipairs(numbers) do`.
- Without L6: 350 tokens (versus 359); removes `local total = 0`.
- Without L7: 344 tokens (versus 359); removes `for position = 1, #number do`.
- Without L8: 320 tokens (versus 359); removes `local digit = tonumber(number:sub(#number - position + 1, #number - position + 1))`.
- Without L9: 343 tokens (versus 359); removes `if position % 2 == 0 then`.
- Without L10: 346 tokens (versus 359); removes `digit = digit * 2`.
- Without L11: 334 tokens (versus 359); removes `if digit > 9 then digit = digit - 9 end`.
- Without L12: 355 tokens (versus 359); removes `end`.
- Without L13: 347 tokens (versus 359); removes `total = total + digit`.
- Without L14: 356 tokens (versus 359); removes `end`.
- Without L15: 343 tokens (versus 359); removes `if total % 10 == 0 then`.
- Without L16: 341 tokens (versus 359); removes `io.write(number, ": valid\n")`.
- Without L17: 356 tokens (versus 359); removes `else`.
- Without L18: 326 tokens (versus 359); removes `local expected = (-(total - tonumber(number:sub(-1)))) % 10`.
- Without L19: 321 tokens (versus 359); removes `io.write(string.format("%s: invalid (expected check digit %d)\n", number, expected))`.
