# Task B selection: 39_prime_factorization / Lua

## Common answer requirements

Trace trial division for supplied value 9973, show why remainder stays unchanged and the square-bound stop occurs, then explain residual-factor insertion and exact output without exponent or separator.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

No integer divisor 2 through 99 divides 9973 (equivalently none of the primes through 97 does), so every remainder test fails and no division/exponent increment happens. Since 99²=9801 <=9973 but 100²=10000 >9973, the trial loop stops at divisor 100 with remainder still 9973. The ordinary-factor positive-exponent branch is never entered. The residual >1 path inserts/prints 9973 directly, without an exponent. An initially empty factor list joins its sole entry with no separator, or an initially true first flag suppresses the separator. The full line is `9973 = 9973` followed by newline.



Source: `main.lua`. Selected original lines: 1,2,3,4,5,6,7,8,9,11,12,13,14,15. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `for _, original in ipairs({84, 9973, 15625, 1001, 123456, 48000, 999958, 999999}) do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    local remaining, divisor, factors = original, 2, {}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    while divisor * divisor <= remaining do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `        local exponent = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        while remaining % divisor == 0 do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `            remaining = remaining // divisor` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            exponent = exponent + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L9: `        if exponent > 0 then` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L12: `        divisor = divisor + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L14: `    if remaining > 1 then factors[#factors + 1] = tostring(remaining) end` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `    io.write(string.format("%d = %s\n", original, table.concat(factors, " * ")))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **264 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **312 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 195 tokens (versus 264); removes `for _, original in ipairs({84, 9973, 15625, 1001, 123456, 48000, 999958, 999999}) do`.
- Without L2: 242 tokens (versus 264); removes `local remaining, divisor, factors = original, 2, {}`.
- Without L3: 249 tokens (versus 264); removes `while divisor * divisor <= remaining do`.
- Without L4: 254 tokens (versus 264); removes `local exponent = 0`.
- Without L5: 248 tokens (versus 264); removes `while remaining % divisor == 0 do`.
- Without L6: 251 tokens (versus 264); removes `remaining = remaining // divisor`.
- Without L7: 251 tokens (versus 264); removes `exponent = exponent + 1`.
- Without L8: 260 tokens (versus 264); removes `end`.
- Without L9: 252 tokens (versus 264); removes `if exponent > 0 then`.
- Without L11: 260 tokens (versus 264); removes `end`.
- Without L12: 252 tokens (versus 264); removes `divisor = divisor + 1`.
- Without L13: 261 tokens (versus 264); removes `end`.
- Without L14: 234 tokens (versus 264); removes `if remaining > 1 then factors[#factors + 1] = tostring(remaining) end`.
- Without L15: 223 tokens (versus 264); removes `io.write(string.format("%d = %s\n", original, table.concat(factors, " * ")))`.
