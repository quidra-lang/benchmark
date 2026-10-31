# Task B selection: 39_prime_factorization / J

## Common answer requirements

Trace trial division for supplied value 9973, show why remainder stays unchanged and the square-bound stop occurs, then explain residual-factor insertion and exact output without exponent or separator.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

No integer divisor 2 through 99 divides 9973 (equivalently none of the primes through 97 does), so every remainder test fails and no division/exponent increment happens. Since 99²=9801 <=9973 but 100²=10000 >9973, the trial loop stops at divisor 100 with remainder still 9973. The ordinary-factor positive-exponent branch is never entered. The residual >1 path inserts/prints 9973 directly, without an exponent. An initially empty factor list joins its sole entry with no separator, or an initially true first flag suppresses the separator. The full line is `9973 = 9973` followed by newline.

The factors box-list starts empty. L20 prefixes each factor with a separator and drops the initial three characters, so a single residual factor produces just 9973.

Source: `main.ijs`. Selected original lines: 2,3,4,5,6,7,8,9,10,11,12,16,17,18,19,20,21. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `  for_original. 84 9973 15625 1001 123456 48000 999958 999999 do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    remaining =. original` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    divisor =. 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    factors =. 0$<''` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    while. (divisor*divisor)<:remaining do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `      exponent =. 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `      while. 0=divisor|remaining do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        remaining =. <.remaining%divisor` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        exponent =. >:exponent` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `      end.` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L12: `      if. exponent>0 do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `      end.` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `      divisor =. >:divisor` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `    end.` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L19: `    if. remaining>1 do. factors =. factors,<":remaining end.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `    joined =. 3}.; (<' * ') ,&.> factors` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `    smoutput (":original),' = ',joined` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **225 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **292 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 171 tokens (versus 225); removes `for_original. 84 9973 15625 1001 123456 48000 999958 999999 do.`.
- Without L3: 218 tokens (versus 225); removes `remaining =. original`.
- Without L4: 218 tokens (versus 225); removes `divisor =. 2`.
- Without L5: 214 tokens (versus 225); removes `factors =. 0$<''`.
- Without L6: 212 tokens (versus 225); removes `while. (divisor*divisor)<:remaining do.`.
- Without L7: 217 tokens (versus 225); removes `exponent =. 0`.
- Without L8: 213 tokens (versus 225); removes `while. 0=divisor|remaining do.`.
- Without L9: 214 tokens (versus 225); removes `remaining =. <.remaining%divisor`.
- Without L10: 216 tokens (versus 225); removes `exponent =. >:exponent`.
- Without L11: 221 tokens (versus 225); removes `end.`.
- Without L12: 215 tokens (versus 225); removes `if. exponent>0 do.`.
- Without L16: 221 tokens (versus 225); removes `end.`.
- Without L17: 216 tokens (versus 225); removes `divisor =. >:divisor`.
- Without L18: 222 tokens (versus 225); removes `end.`.
- Without L19: 203 tokens (versus 225); removes `if. remaining>1 do. factors =. factors,<":remaining end.`.
- Without L20: 201 tokens (versus 225); removes `joined =. 3}.; (<' * ') ,&.> factors`.
- Without L21: 208 tokens (versus 225); removes `smoutput (":original),' = ',joined`.
