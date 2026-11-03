# Task B selection: 41_quadratic_roots / Dart

## Common answer requirements

For (-2,5,4), derive discriminant and both quadratic-formula values; explain why the negative denominator makes the minus-root value larger; identify source ordering and its preservation in printed x1/x2.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The discriminant is 5²−4(−2)(4)=57>0. With denominator−4, the +sqrt value is (−5+sqrt57)/(−4)≈−0.6374586088 and the −sqrt value is (−5−sqrt57)/(−4)≈3.1374586088. Thus formula order alone is not descending. The selected max/min expressions or conditional swap explicitly put the larger value first; x1 prints 3.1375 and x2 prints −0.6375 with four fractional digits. The distinct-real branch is selected because 57 is positive.

The original list row [-2,5,4] and s bindings identify the case. StringBuffer’s retained stdout sink demonstrates that ordered formatted fields are printed.

Source: `main.dart`. Selected original lines: 5,6,8,14,15,17,18,19,20,21,33. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L5: `  final out = StringBuffer();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `  for (final s in [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    [-2, 5, 4],` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    final a = s[0], b = s[1], c = s[2], disc = b * b - 4 * a * c;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `    final numerator = -b.toDouble(), denominator = 2.0 * a;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `    if (disc > 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `      final r1 = (numerator + math.sqrt(disc)) / denominator,` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `          r2 = (numerator - math.sqrt(disc)) / denominator;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `      out.write(` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `        'x1 = ${math.max(r1, r2).toStringAsFixed(4)}, x2 = ${math.min(r1, r2).toStringAsFixed(4)}',` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L33: `  stdout.write(out);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **259 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **584 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L5: 246 tokens (versus 259); removes `final out = StringBuffer();`.
- Without L6: 247 tokens (versus 259); removes `for (final s in [`.
- Without L8: 246 tokens (versus 259); removes `[-2, 5, 4],`.
- Without L14: 203 tokens (versus 259); removes `final a = s[0], b = s[1], c = s[2], disc = b * b - 4 * a * c;`.
- Without L15: 230 tokens (versus 259); removes `final numerator = -b.toDouble(), denominator = 2.0 * a;`.
- Without L17: 246 tokens (versus 259); removes `if (disc > 0) {`.
- Without L18: 233 tokens (versus 259); removes `final r1 = (numerator + math.sqrt(disc)) / denominator,`.
- Without L19: 234 tokens (versus 259); removes `r2 = (numerator - math.sqrt(disc)) / denominator;`.
- Without L20: 252 tokens (versus 259); removes `out.write(`.
- Without L21: 203 tokens (versus 259); removes `'x1 = ${math.max(r1, r2).toStringAsFixed(4)}, x2 = ${math.min(r1, r2).toStringAsFixed(4)}',`.
- Without L33: 250 tokens (versus 259); removes `stdout.write(out);`.
