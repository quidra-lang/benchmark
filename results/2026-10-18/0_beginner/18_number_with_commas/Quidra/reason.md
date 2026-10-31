# Task B selection: 18_number_with_commas / Quidra

## Common answer requirements

Trace -456789 to its exact grouped output, identify right-based three-digit boundaries and sign placement, and explain why sign is excluded and no comma follows it.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The magnitude digits are456789, partitioned from the right into456|789, so the output line is `-456,789` followed by newline. Manual implementations strip/skip the sign or format the absolute magnitude, print/prepend minus separately, and insert a comma only before a nonfirst digit whose remaining digit count is divisible by3. This gives the one boundary before7; a guard excluding the first digit prevents a comma immediately after minus. Regex/library implementations perform equivalent numeric-digit grouping, preserving minus as sign rather than including it as a digit.



Source: `main.qui`. Selected original lines: 1-10. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `int[] values = [0, 7, 999, 1000, -456789, 3141592, 9876543210]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `for int value = values[]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    int magnitude = if value < 0 then -value else value` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    string digits = magnitude.string()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    string result = if value < 0 then "-" else ""` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    for 0 <= int index < int(len(digits))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        if index > 0 and (int(len(digits)) - index) % 3 == 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `            result += ","` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        result += digits[index]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    print(result + NL)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **216 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **216 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 161 tokens (versus 216); removes `int[] values = [0, 7, 999, 1000, -456789, 3141592, 9876543210]`.
- Without L2: 205 tokens (versus 216); removes `for int value = values[]`.
- Without L3: 192 tokens (versus 216); removes `int magnitude = if value < 0 then -value else value`.
- Without L4: 203 tokens (versus 216); removes `string digits = magnitude.string()`.
- Without L5: 190 tokens (versus 216); removes `string result = if value < 0 then "-" else ""`.
- Without L6: 195 tokens (versus 216); removes `for 0 <= int index < int(len(digits))`.
- Without L7: 182 tokens (versus 216); removes `if index > 0 and (int(len(digits)) - index) % 3 == 0`.
- Without L8: 205 tokens (versus 216); removes `result += ","`.
- Without L9: 205 tokens (versus 216); removes `result += digits[index]`.
- Without L10: 206 tokens (versus 216); removes `print(result + NL)`.
