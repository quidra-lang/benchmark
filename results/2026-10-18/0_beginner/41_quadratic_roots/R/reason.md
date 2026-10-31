# Task B selection: 41_quadratic_roots / R

## Common answer requirements

For (-2,5,4), derive discriminant and both quadratic-formula values; explain why the negative denominator makes the minus-root value larger; identify source ordering and its preservation in printed x1/x2.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The discriminant is 5²−4(−2)(4)=57>0. With denominator−4, the +sqrt value is (−5+sqrt57)/(−4)≈−0.6374586088 and the −sqrt value is (−5−sqrt57)/(−4)≈3.1374586088. Thus formula order alone is not descending. The selected max/min expressions or conditional swap explicitly put the larger value first; x1 prints 3.1375 and x2 prints −0.6375 with four fractional digits. The distinct-real branch is selected because 57 is positive.



Source: `main.R`. Selected original lines: 1-6,8-11. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `coefficients <- list(c(1L, -3L, -10L), c(-2L, 5L, 4L), c(3L, 1L, -2L), c(4L, -12L, 9L), c(1L, 2L, 5L), c(-2L, 3L, -4L))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `for (coefficient in coefficients) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `  a <- coefficient[1]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `  b <- coefficient[2]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `  c_value <- coefficient[3]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `  discriminant <- b * b - 4L * a * c_value` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `  if (discriminant > 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    first <- (-b + sqrt(discriminant)) / (2 * a)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    second <- (-b - sqrt(discriminant)) / (2 * a)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    cat(sprintf("x1 = %.4f, x2 = %.4f\n", max(first, second), min(first, second)))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **288 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **470 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 183 tokens (versus 288); removes `coefficients <- list(c(1L, -3L, -10L), c(-2L, 5L, 4L), c(3L, 1L, -2L), c(4L, -12L, 9L), c(1L, 2L, 5L), c(-2L, 3L, -4L))`.
- Without L2: 276 tokens (versus 288); removes `for (coefficient in coefficients) {`.
- Without L3: 278 tokens (versus 288); removes `a <- coefficient[1]`.
- Without L4: 278 tokens (versus 288); removes `b <- coefficient[2]`.
- Without L5: 276 tokens (versus 288); removes `c_value <- coefficient[3]`.
- Without L6: 262 tokens (versus 288); removes `discriminant <- b * b - 4L * a * c_value`.
- Without L8: 275 tokens (versus 288); removes `if (discriminant > 0) {`.
- Without L9: 261 tokens (versus 288); removes `first <- (-b + sqrt(discriminant)) / (2 * a)`.
- Without L10: 261 tokens (versus 288); removes `second <- (-b - sqrt(discriminant)) / (2 * a)`.
- Without L11: 242 tokens (versus 288); removes `cat(sprintf("x1 = %.4f, x2 = %.4f\n", max(first, second), min(first, second)))`.
