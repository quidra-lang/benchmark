# Task B selection: 41_quadratic_roots / Quidra

## Common answer requirements

For (-2,5,4), derive discriminant and both quadratic-formula values; explain why the negative denominator makes the minus-root value larger; identify source ordering and its preservation in printed x1/x2.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The discriminant is 5²−4(−2)(4)=57>0. With denominator−4, the +sqrt value is (−5+sqrt57)/(−4)≈−0.6374586088 and the −sqrt value is (−5−sqrt57)/(−4)≈3.1374586088. Thus formula order alone is not descending. The selected max/min expressions or conditional swap explicitly put the larger value first; x1 prints 3.1375 and x2 prints −0.6375 with four fractional digits. The distinct-real branch is selected because 57 is positive.

The tuple swap executes when first<second, then the print interpolates first as x1 and second as x2.

Source: `main.qui`. Selected original lines: 3-9,11-17. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `int[][] coefficients = [[1, -3, -10], [-2, 5, 4], [3, 1, -2], [4, -12, 9], [1, 2, 5], [-2, 3, -4]]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `for int[] row = coefficients[]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    int a = row[0]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    int b = row[1]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    int c = row[2]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    int d = b * b - 4 * a * c` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    real64 denominator = real64(2 * a)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    if d > 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        real64 root = math.sqrt(real64(d))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        real64 first = (real64(-b) + root) / denominator` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        real64 second = (real64(-b) - root) / denominator` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `        if first < second` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `            (first, second) = (second, first)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `        print("x1 = {first:frac=4}, x2 = {second:frac=4}{NL}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **310 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **544 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 228 tokens (versus 310); removes `int[][] coefficients = [[1, -3, -10], [-2, 5, 4], [3, 1, -2], [4, -12, 9], [1, 2, 5], [-2, 3, -4]]`.
- Without L4: 298 tokens (versus 310); removes `for int[] row = coefficients[]`.
- Without L5: 298 tokens (versus 310); removes `int a = row[0]`.
- Without L6: 298 tokens (versus 310); removes `int b = row[1]`.
- Without L7: 298 tokens (versus 310); removes `int c = row[2]`.
- Without L8: 285 tokens (versus 310); removes `int d = b * b - 4 * a * c`.
- Without L9: 294 tokens (versus 310); removes `real64 denominator = real64(2 * a)`.
- Without L11: 301 tokens (versus 310); removes `if d > 0`.
- Without L12: 292 tokens (versus 310); removes `real64 root = math.sqrt(real64(d))`.
- Without L13: 286 tokens (versus 310); removes `real64 first = (real64(-b) + root) / denominator`.
- Without L14: 286 tokens (versus 310); removes `real64 second = (real64(-b) - root) / denominator`.
- Without L15: 300 tokens (versus 310); removes `if first < second`.
- Without L16: 291 tokens (versus 310); removes `(first, second) = (second, first)`.
- Without L17: 275 tokens (versus 310); removes `print("x1 = {first:frac=4}, x2 = {second:frac=4}{NL}")`.
