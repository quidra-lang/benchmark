# Task B selection: 41_quadratic_roots / C++

## Common answer requirements

For (-2,5,4), derive discriminant and both quadratic-formula values; explain why the negative denominator makes the minus-root value larger; identify source ordering and its preservation in printed x1/x2.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The discriminant is 5²−4(−2)(4)=57>0. With denominator−4, the +sqrt value is (−5+sqrt57)/(−4)≈−0.6374586088 and the −sqrt value is (−5−sqrt57)/(−4)≈3.1374586088. Thus formula order alone is not descending. The selected max/min expressions or conditional swap explicitly put the larger value first; x1 prints 3.1375 and x2 prints −0.6375 with four fractional digits. The distinct-real branch is selected because 57 is positive.

The requested fact is root ordering in x1/x2 fields, for which the selected max/min output is sufficient. Unchanged global formatting setup does not change this ordering.

Source: `main.cpp`. Selected original lines: 7,9-10,12-15. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `    int coefficients[][3] = {{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3, -4}};` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    for (auto [a, b, c] : coefficients) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        int d = b * b - 4 * a * c;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        if (d > 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            double root = std::sqrt(d);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `            double x = (-b + root) / (2.0 * a), y = (-b - root) / (2.0 * a);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `            std::cout << "x1 = " << std::max(x, y) << ", x2 = " << std::min(x, y) << '\n';` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **285 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **577 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 197 tokens (versus 285); removes `int coefficients[][3] = {{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3, -4}};`.
- Without L9: 262 tokens (versus 285); removes `for (auto [a, b, c] : coefficients) {`.
- Without L10: 258 tokens (versus 285); removes `int d = b * b - 4 * a * c;`.
- Without L12: 271 tokens (versus 285); removes `if (d > 0) {`.
- Without L13: 268 tokens (versus 285); removes `double root = std::sqrt(d);`.
- Without L14: 228 tokens (versus 285); removes `double x = (-b + root) / (2.0 * a), y = (-b - root) / (2.0 * a);`.
- Without L15: 226 tokens (versus 285); removes `std::cout << "x1 = " << std::max(x, y) << ", x2 = " << std::min(x, y) << '\n';`.
