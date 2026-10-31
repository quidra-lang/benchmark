# Task B selection: 33_yen_change / Lua

## Common answer requirements

Trace 506 through the source denomination order, quotient/remainder transitions, omission of zero quantities, piece accumulation, and exact complete output line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

For 506, 10000/5000/1000 give zero and do not change remaining. At 500 the quotient is 1 and remainder 6; at 100,50,10 the quotient is zero; at 5 the quotient is 1 and remainder 1; at 1 the quotient is 1 and remainder 0. The positive-count guard omits zero-piece denominations. Adding the three positive quantities gives 3. The exact line is `506 yen: 500x1 5x1 1x1 (3 pieces)` followed by newline.



Source: `main.lua`. Selected original lines: 1,2,3,4,5,6,7,8,9,10,11. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `for _, amount in ipairs({3780, 15420, 99999, 506, 48263}) do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    local remaining, total, pieces = amount, 0, {}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    for _, face in ipairs({10000, 5000, 1000, 500, 100, 50, 10, 5, 1}) do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `        local quantity = remaining // face` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        remaining = remaining % face` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        if quantity > 0 then` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            pieces[#pieces + 1] = string.format("%dx%d", face, quantity)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `            total = total + quantity` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L10: `    end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L11: `    io.write(string.format("%d yen: %s (%d pieces)\n", amount, table.concat(pieces, " "), total))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **267 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **269 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 220 tokens (versus 267); removes `for _, amount in ipairs({3780, 15420, 99999, 506, 48263}) do`.
- Without L2: 245 tokens (versus 267); removes `local remaining, total, pieces = amount, 0, {}`.
- Without L3: 208 tokens (versus 267); removes `for _, face in ipairs({10000, 5000, 1000, 500, 100, 50, 10, 5, 1}) do`.
- Without L4: 253 tokens (versus 267); removes `local quantity = remaining // face`.
- Without L5: 255 tokens (versus 267); removes `remaining = remaining % face`.
- Without L6: 255 tokens (versus 267); removes `if quantity > 0 then`.
- Without L7: 236 tokens (versus 267); removes `pieces[#pieces + 1] = string.format("%dx%d", face, quantity)`.
- Without L8: 254 tokens (versus 267); removes `total = total + quantity`.
- Without L9: 263 tokens (versus 267); removes `end`.
- Without L10: 264 tokens (versus 267); removes `end`.
- Without L11: 217 tokens (versus 267); removes `io.write(string.format("%d yen: %s (%d pieces)\n", amount, table.concat(pieces, " "), total))`.
