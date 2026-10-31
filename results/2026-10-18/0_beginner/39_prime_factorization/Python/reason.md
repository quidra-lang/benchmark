# Task B selection: 39_prime_factorization / Python

## Common answer requirements

Trace trial division for supplied value 9973, show why remainder stays unchanged and the square-bound stop occurs, then explain residual-factor insertion and exact output without exponent or separator.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

No integer divisor 2 through 99 divides 9973 (equivalently none of the primes through 97 does), so every remainder test fails and no division/exponent increment happens. Since 99²=9801 <=9973 but 100²=10000 >9973, the trial loop stops at divisor 100 with remainder still 9973. The ordinary-factor positive-exponent branch is never entered. The residual >1 path inserts/prints 9973 directly, without an exponent. An initially empty factor list joins its sole entry with no separator, or an initially true first flag suppresses the separator. The full line is `9973 = 9973` followed by newline.



Source: `main.py`. Selected original lines: 1-9,11-14. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `for number in [84, 9973, 15625, 1001, 123456, 48000, 999958, 999999]:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    remaining, divisor = number, 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    factors = []` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    while divisor * divisor <= remaining:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        exponent = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        while remaining % divisor == 0:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            remaining //= divisor` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `            exponent += 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        if exponent:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        divisor += 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `    if remaining > 1:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        factors.append(str(remaining))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    print(f"{number} = {' * '.join(factors)}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **199 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **233 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 138 tokens (versus 199); removes `for number in [84, 9973, 15625, 1001, 123456, 48000, 999958, 999999]:`.
- Without L2: 186 tokens (versus 199); removes `remaining, divisor = number, 2`.
- Without L3: 192 tokens (versus 199); removes `factors = []`.
- Without L4: 185 tokens (versus 199); removes `while divisor * divisor <= remaining:`.
- Without L5: 191 tokens (versus 199); removes `exponent = 0`.
- Without L6: 184 tokens (versus 199); removes `while remaining % divisor == 0:`.
- Without L7: 190 tokens (versus 199); removes `remaining //= divisor`.
- Without L8: 190 tokens (versus 199); removes `exponent += 1`.
- Without L9: 192 tokens (versus 199); removes `if exponent:`.
- Without L11: 191 tokens (versus 199); removes `divisor += 1`.
- Without L12: 189 tokens (versus 199); removes `if remaining > 1:`.
- Without L13: 187 tokens (versus 199); removes `factors.append(str(remaining))`.
- Without L14: 173 tokens (versus 199); removes `print(f"{number} = {' * '.join(factors)}")`.
