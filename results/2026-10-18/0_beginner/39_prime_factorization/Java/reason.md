# Task B selection: 39_prime_factorization / Java

## Common answer requirements

Trace trial division for supplied value 9973, show why remainder stays unchanged and the square-bound stop occurs, then explain residual-factor insertion and exact output without exponent or separator.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

No integer divisor 2 through 99 divides 9973 (equivalently none of the primes through 97 does), so every remainder test fails and no division/exponent increment happens. Since 99²=9801 <=9973 but 100²=10000 >9973, the trial loop stops at divisor 100 with remainder still 9973. The ordinary-factor positive-exponent branch is never entered. The residual >1 path inserts/prints 9973 directly, without an exponent. An initially empty factor list joins its sole entry with no separator, or an initially true first flag suppresses the separator. The full line is `9973 = 9973` followed by newline.



Source: `Main.java`. Selected original lines: 6,7,8,9,10,11,12,13,14,15,17,18,19,20,22. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L6: `        for (int n : new int[]{84, 9973, 15625, 1001, 123456, 48000, 999958, 999999}) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            int remaining = n;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `            List<String> factors = new ArrayList<>();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `            for (int d = 2; d * d <= remaining; d++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `                int exponent = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `                while (remaining % d == 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `                    remaining /= d;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `                    exponent++;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `                }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `                if (exponent > 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `                }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L18: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L19: `            if (remaining > 1) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `                factors.add(Integer.toString(remaining));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `            System.out.println(n + " = " + String.join(" * ", factors));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **296 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **393 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L6: 223 tokens (versus 296); removes `for (int n : new int[]{84, 9973, 15625, 1001, 123456, 48000, 999958, 999999}) {`.
- Without L7: 284 tokens (versus 296); removes `int remaining = n;`.
- Without L8: 274 tokens (versus 296); removes `List<String> factors = new ArrayList<>();`.
- Without L9: 264 tokens (versus 296); removes `for (int d = 2; d * d <= remaining; d++) {`.
- Without L10: 283 tokens (versus 296); removes `int exponent = 0;`.
- Without L11: 276 tokens (versus 296); removes `while (remaining % d == 0) {`.
- Without L12: 284 tokens (versus 296); removes `remaining /= d;`.
- Without L13: 287 tokens (versus 296); removes `exponent++;`.
- Without L14: 290 tokens (versus 296); removes `}`.
- Without L15: 280 tokens (versus 296); removes `if (exponent > 0) {`.
- Without L17: 290 tokens (versus 296); removes `}`.
- Without L18: 291 tokens (versus 296); removes `}`.
- Without L19: 281 tokens (versus 296); removes `if (remaining > 1) {`.
- Without L20: 278 tokens (versus 296); removes `factors.add(Integer.toString(remaining));`.
- Without L22: 259 tokens (versus 296); removes `System.out.println(n + " = " + String.join(" * ", factors));`.
