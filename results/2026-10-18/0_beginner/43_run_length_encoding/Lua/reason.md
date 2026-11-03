# Task B selection: 43_run_length_encoding / Lua

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.



Source: `main.lua`. Selected original lines: 1,2,3,4,5,6,7,8,9,12,13,14,15,18,19,22,23,24. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `local function encode(source)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    local result, i = {}, 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    while i <= #source do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `        local j = i + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        while j <= #source and source:sub(j, j) == source:sub(i, i) do j = j + 1 end` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        result[#result + 1] = tostring(j - i) .. source:sub(i, i)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        i = j` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L9: `    return table.concat(result)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `local function decode(encoded)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    local result = {}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    for count, letter in encoded:gmatch("(%d+)([A-Z])") do result[#result + 1] = string.rep(letter, tonumber(count)) end` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `    return table.concat(result)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `local sources = {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `    "AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `for _, source in ipairs(sources) do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `    local encoded = encode(source)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `    io.write(source, " -> ", encoded, " -> ", decode(encoded), "\n")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **338 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **354 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 329 tokens (versus 338); removes `local function encode(source)`.
- Without L2: 322 tokens (versus 338); removes `local result, i = {}, 1`.
- Without L3: 326 tokens (versus 338); removes `while i <= #source do`.
- Without L4: 324 tokens (versus 338); removes `local j = i + 1`.
- Without L5: 289 tokens (versus 338); removes `while j <= #source and source:sub(j, j) == source:sub(i, i) do j = j + 1 end`.
- Without L6: 303 tokens (versus 338); removes `result[#result + 1] = tostring(j - i) .. source:sub(i, i)`.
- Without L7: 330 tokens (versus 338); removes `i = j`.
- Without L8: 335 tokens (versus 338); removes `end`.
- Without L9: 328 tokens (versus 338); removes `return table.concat(result)`.
- Without L12: 329 tokens (versus 338); removes `local function decode(encoded)`.
- Without L13: 328 tokens (versus 338); removes `local result = {}`.
- Without L14: 279 tokens (versus 338); removes `for count, letter in encoded:gmatch("(%d+)([A-Z])") do result[#result + 1] = string.rep(letter, tonumber(count)) end`.
- Without L15: 328 tokens (versus 338); removes `return table.concat(result)`.
- Without L18: 330 tokens (versus 338); removes `local sources = {`.
- Without L19: 317 tokens (versus 338); removes `"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",`.
- Without L22: 322 tokens (versus 338); removes `for _, source in ipairs(sources) do`.
- Without L23: 326 tokens (versus 338); removes `local encoded = encode(source)`.
- Without L24: 301 tokens (versus 338); removes `io.write(source, " -> ", encoded, " -> ", decode(encoded), "\n")`.
