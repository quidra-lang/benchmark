# Task B selection: 41_quadratic_roots / C

## Common answer requirements

For (-2,5,4), derive discriminant and both quadratic-formula values; explain why the negative denominator makes the minus-root value larger; identify source ordering and its preservation in printed x1/x2.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The discriminant is 5²−4(−2)(4)=57>0. With denominator−4, the +sqrt value is (−5+sqrt57)/(−4)≈−0.6374586088 and the −sqrt value is (−5−sqrt57)/(−4)≈3.1374586088. Thus formula order alone is not descending. The selected max/min expressions or conditional swap explicitly put the larger value first; x1 prints 3.1375 and x2 prints −0.6375 with four fractional digits. The distinct-real branch is selected because 57 is positive.

The x<y test is true for this negative-denominator case. The temporary and two assignments implement the swap, and the selected print passes x then y.

Source: `main.c`. Selected original lines: 6,8,9,11,12,13,14,15,16,17,18,19. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L6: `    int coefficients[][3] = {{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3, -4}};` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        int a = coefficients[i][0], b = coefficients[i][1], c = coefficients[i][2];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        int d = b * b - 4 * a * c;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        if (d > 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `            double root = sqrt((double)d);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            double x = (-b + root) / (2.0 * a), y = (-b - root) / (2.0 * a);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `            if (x < y) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `                double t = x;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `                x = y;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `                y = t;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L19: `            printf("x1 = %.4f, x2 = %.4f\n", x, y);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **336 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **604 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L6: 248 tokens (versus 336); removes `int coefficients[][3] = {{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3, -4}};`.
- Without L8: 293 tokens (versus 336); removes `int a = coefficients[i][0], b = coefficients[i][1], c = coefficients[i][2];`.
- Without L9: 309 tokens (versus 336); removes `int d = b * b - 4 * a * c;`.
- Without L11: 322 tokens (versus 336); removes `if (d > 0) {`.
- Without L12: 318 tokens (versus 336); removes `double root = sqrt((double)d);`.
- Without L13: 279 tokens (versus 336); removes `double x = (-b + root) / (2.0 * a), y = (-b - root) / (2.0 * a);`.
- Without L14: 321 tokens (versus 336); removes `if (x < y) {`.
- Without L15: 323 tokens (versus 336); removes `double t = x;`.
- Without L16: 325 tokens (versus 336); removes `x = y;`.
- Without L17: 325 tokens (versus 336); removes `y = t;`.
- Without L18: 331 tokens (versus 336); removes `}`.
- Without L19: 302 tokens (versus 336); removes `printf("x1 = %.4f, x2 = %.4f\n", x, y);`.
