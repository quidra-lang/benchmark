# Task B selection: 18_number_with_commas / Lua

## Common answer requirements

Trace -456789 to its exact grouped output, identify right-based three-digit boundaries and sign placement, and explain why sign is excluded and no comma follows it.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The magnitude digits are456789, partitioned from the right into456|789, so the output line is `-456,789` followed by newline. Manual implementations strip/skip the sign or format the absolute magnitude, print/prepend minus separately, and insert a comma only before a nonfirst digit whose remaining digit count is divisible by3. This gives the one boundary before7; a guard excluding the first digit prevents a comma immediately after minus. Regex/library implementations perform equivalent numeric-digit grouping, preserving minus as sign rather than including it as a digit.

Reverse the magnitude digits to987654, append a comma after each three-digit match, reverse back, then remove a possible initial comma. Only after grouping does the separate minus prefix join the result.

Source: `main.lua`. Selected original lines: 1-4. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `for _, n in ipairs({0, 7, 999, 1000, -456789, 3141592, 9876543210}) do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    local digits = tostring(math.abs(n))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    io.write(n < 0 and "-" or "", grouped, "\n")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **159 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **161 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 97 tokens (versus 159); removes `for _, n in ipairs({0, 7, 999, 1000, -456789, 3141592, 9876543210}) do`.
- Without L2: 142 tokens (versus 159); removes `local digits = tostring(math.abs(n))`.
- Without L3: 111 tokens (versus 159); removes `local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")`.
- Without L4: 127 tokens (versus 159); removes `io.write(n < 0 and "-" or "", grouped, "\n")`.
