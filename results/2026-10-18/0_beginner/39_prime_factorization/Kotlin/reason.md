# Task B selection: 39_prime_factorization / Kotlin

## Common answer requirements

Trace trial division for supplied value 9973, show why remainder stays unchanged and the square-bound stop occurs, then explain residual-factor insertion and exact output without exponent or separator.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

No integer divisor 2 through 99 divides 9973 (equivalently none of the primes through 97 does), so every remainder test fails and no division/exponent increment happens. Since 99²=9801 <=9973 but 100²=10000 >9973, the trial loop stops at divisor 100 with remainder still 9973. The ordinary-factor positive-exponent branch is never entered. The residual >1 path inserts/prints 9973 directly, without an exponent. An initially empty factor list joins its sole entry with no separator, or an initially true first flag suppresses the separator. The full line is `9973 = 9973` followed by newline.



Source: `main.kt`. Selected original lines: 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    for (n in intArrayOf(84, 9973, 15625, 1001, 123456, 48000, 999958, 999999)) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `        var remaining = n` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `        var d = 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        val factors = mutableListOf<String>()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        while (d * d <= remaining) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            var exponent = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `            while (remaining % d == 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `                remaining /= d` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `                exponent++` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L12: `            if (exponent > 0) factors.add("$d" + if (exponent > 1) "^$exponent" else "")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            d++` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `        if (remaining > 1) factors.add(remaining.toString())` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `        println("$n = ${factors.joinToString(" * ")}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **284 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **297 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 215 tokens (versus 284); removes `for (n in intArrayOf(84, 9973, 15625, 1001, 123456, 48000, 999958, 999999)) {`.
- Without L3: 274 tokens (versus 284); removes `var remaining = n`.
- Without L4: 274 tokens (versus 284); removes `var d = 2`.
- Without L5: 267 tokens (versus 284); removes `val factors = mutableListOf<String>()`.
- Without L6: 266 tokens (versus 284); removes `while (d * d <= remaining) {`.
- Without L7: 273 tokens (versus 284); removes `var exponent = 0`.
- Without L8: 265 tokens (versus 284); removes `while (remaining % d == 0) {`.
- Without L9: 274 tokens (versus 284); removes `remaining /= d`.
- Without L10: 277 tokens (versus 284); removes `exponent++`.
- Without L11: 279 tokens (versus 284); removes `}`.
- Without L12: 238 tokens (versus 284); removes `if (exponent > 0) factors.add("$d" + if (exponent > 1) "^$exponent" else "")`.
- Without L13: 278 tokens (versus 284); removes `d++`.
- Without L14: 280 tokens (versus 284); removes `}`.
- Without L15: 260 tokens (versus 284); removes `if (remaining > 1) factors.add(remaining.toString())`.
- Without L16: 256 tokens (versus 284); removes `println("$n = ${factors.joinToString(" * ")}")`.
