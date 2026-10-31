# Task B selection: 40_binary_search / Lua

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.

numbers[mid+1] adjusts Lua’s one-based sequence storage; probes append to its end.

Source: `main.lua`. Selected original lines: 1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `local numbers = {3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `for _, target in ipairs({42, 3, 77, 31, 50, 1}) do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    local lo, hi, found, probes = 0, #numbers - 1, -1, {}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    while lo <= hi do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        local mid = (lo + hi) // 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        probes[#probes + 1] = mid` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        if numbers[mid + 1] == target then` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `            found = mid` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        elseif numbers[mid + 1] < target then` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            lo = mid + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        else` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            hi = mid - 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `    end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L16: `    local result = found >= 0 and string.format("index %d", found) or "not found"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `    io.write(string.format("%d: probes %s -> %s\n", target, table.concat(probes, " "), result))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **356 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **363 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 287 tokens (versus 356); removes `local numbers = {3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77}`.
- Without L2: 319 tokens (versus 356); removes `for _, target in ipairs({42, 3, 77, 31, 50, 1}) do`.
- Without L3: 322 tokens (versus 356); removes `local lo, hi, found, probes = 0, #numbers - 1, -1, {}`.
- Without L4: 345 tokens (versus 356); removes `while lo <= hi do`.
- Without L5: 336 tokens (versus 356); removes `local mid = (lo + hi) // 2`.
- Without L6: 340 tokens (versus 356); removes `probes[#probes + 1] = mid`.
- Without L7: 337 tokens (versus 356); removes `if numbers[mid + 1] == target then`.
- Without L8: 347 tokens (versus 356); removes `found = mid`.
- Without L10: 337 tokens (versus 356); removes `elseif numbers[mid + 1] < target then`.
- Without L11: 343 tokens (versus 356); removes `lo = mid + 1`.
- Without L12: 352 tokens (versus 356); removes `else`.
- Without L13: 343 tokens (versus 356); removes `hi = mid - 1`.
- Without L14: 352 tokens (versus 356); removes `end`.
- Without L15: 353 tokens (versus 356); removes `end`.
- Without L16: 318 tokens (versus 356); removes `local result = found >= 0 and string.format("index %d", found) or "not found"`.
- Without L17: 309 tokens (versus 356); removes `io.write(string.format("%d: probes %s -> %s\n", target, table.concat(probes, " "), result))`.
