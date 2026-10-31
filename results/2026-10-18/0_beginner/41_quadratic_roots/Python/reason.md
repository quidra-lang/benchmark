# Task B selection: 41_quadratic_roots / Python

## Common answer requirements

For (-2,5,4), derive discriminant and both quadratic-formula values; explain why the negative denominator makes the minus-root value larger; identify source ordering and its preservation in printed x1/x2.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The discriminant is 5²−4(−2)(4)=57>0. With denominator−4, the +sqrt value is (−5+sqrt57)/(−4)≈−0.6374586088 and the −sqrt value is (−5−sqrt57)/(−4)≈3.1374586088. Thus formula order alone is not descending. The selected max/min expressions or conditional swap explicitly put the larger value first; x1 prints 3.1375 and x2 prints −0.6375 with four fractional digits. The distinct-real branch is selected because 57 is positive.



Source: `main.py`. Selected original lines: 3,5,11-15,17,24. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `for a, b, c in [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    (-2, 5, 4),` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    discriminant = b * b - 4 * a * c` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `    if discriminant > 0:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        roots = [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `            (-b + sqrt(discriminant)) / (2 * a),` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `            (-b - sqrt(discriminant)) / (2 * a),` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `        result = f"x1 = {max(roots):.4f}, x2 = {min(roots):.4f}"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `    print(f"{a} {b} {c}: {result}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **181 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **405 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 167 tokens (versus 181); removes `for a, b, c in [`.
- Without L5: 168 tokens (versus 181); removes `(-2, 5, 4),`.
- Without L11: 158 tokens (versus 181); removes `discriminant = b * b - 4 * a * c`.
- Without L12: 171 tokens (versus 181); removes `if discriminant > 0:`.
- Without L13: 173 tokens (versus 181); removes `roots = [`.
- Without L14: 155 tokens (versus 181); removes `(-b + sqrt(discriminant)) / (2 * a),`.
- Without L15: 155 tokens (versus 181); removes `(-b - sqrt(discriminant)) / (2 * a),`.
- Without L17: 143 tokens (versus 181); removes `result = f"x1 = {max(roots):.4f}, x2 = {min(roots):.4f}"`.
- Without L24: 158 tokens (versus 181); removes `print(f"{a} {b} {c}: {result}")`.
