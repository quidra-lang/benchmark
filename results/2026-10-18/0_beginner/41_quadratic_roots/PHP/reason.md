# Task B selection: 41_quadratic_roots / PHP

## Common answer requirements

For (-2,5,4), derive discriminant and both quadratic-formula values; explain why the negative denominator makes the minus-root value larger; identify source ordering and its preservation in printed x1/x2.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The discriminant is 5²−4(−2)(4)=57>0. With denominator−4, the +sqrt value is (−5+sqrt57)/(−4)≈−0.6374586088 and the −sqrt value is (−5−sqrt57)/(−4)≈3.1374586088. Thus formula order alone is not descending. The selected max/min expressions or conditional swap explicitly put the larger value first; x1 prints 3.1375 and x2 prints −0.6375 with four fractional digits. The distinct-real branch is selected because 57 is positive.



Source: `main.php`. Selected original lines: 3-4,6-9. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `foreach ([[1, -3, -10], [-2, 5, 4], [3, 1, -2], [4, -12, 9], [1, 2, 5], [-2, 3, -4]] as [$a, $b, $c]) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    $discriminant = $b * $b - 4 * $a * $c;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    if ($discriminant > 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        $first = (-$b + sqrt($discriminant)) / (2 * $a);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        $second = (-$b - sqrt($discriminant)) / (2 * $a);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        printf("x1 = %.4F, x2 = %.4F\n", max($first, $second), min($first, $second));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **253 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **452 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 158 tokens (versus 253); removes `foreach ([[1, -3, -10], [-2, 5, 4], [3, 1, -2], [4, -12, 9], [1, 2, 5], [-2, 3, -4]] as [$a, $b, $c]) {`.
- Without L4: 224 tokens (versus 253); removes `$discriminant = $b * $b - 4 * $a * $c;`.
- Without L6: 239 tokens (versus 253); removes `if ($discriminant > 0) {`.
- Without L7: 220 tokens (versus 253); removes `$first = (-$b + sqrt($discriminant)) / (2 * $a);`.
- Without L8: 220 tokens (versus 253); removes `$second = (-$b - sqrt($discriminant)) / (2 * $a);`.
- Without L9: 204 tokens (versus 253); removes `printf("x1 = %.4F, x2 = %.4F\n", max($first, $second), min($first, $second));`.
