# Task B selection: 44_luhn_checksum / Dart

## Common answer requirements

Explain leading-zero preservation of 0128469655154 as a digit string through validation/output; identify alternating doubled positions counting from the right; explain expected replacement of the rightmost check digit on failure.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The membership value is stored as text, including its leading0, and output uses that original text. Individual character-to-digit conversions create arithmetic values without converting/replacing the full string. Counting from the right with check digit at position1, double positions2,4,6,8,10,12; equivalently use odd zero-based reverse indices, or even length−i for a forward zero-based scan. Values above9 after doubling lose9. For this number, transformed digits from the right are 4,1,1,1,5,3,9,3,4,7,2,2,0, totaling42, so validation fails. Subtract the undoubled rightmost4 to get38; the nonnegative modulo-10 complement gives expected check digit2. Reporting keeps the original leading-zero string.



Source: `main.dart`. Selected original lines: 2,4,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `  for (final number in [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    '0128469655154',` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    var sum = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    for (var i = 0; i < number.length; i++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `      var v = number.codeUnitAt(i) - 48;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `      if ((number.length - i) % 2 == 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        v *= 2;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `        if (v > 9) v -= 9;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `      }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `      sum += v;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L19: `    if (sum % 10 == 0) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `      print('$number: valid');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `    } else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L22: `      final without = sum - (number.codeUnitAt(number.length - 1) - 48);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `      print(` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `        '$number: invalid (expected check digit ${(10 - without % 10) % 10})',` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **281 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **406 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 269 tokens (versus 281); removes `for (final number in [`.
- Without L4: 263 tokens (versus 281); removes `'0128469655154',`.
- Without L10: 271 tokens (versus 281); removes `var sum = 0;`.
- Without L11: 253 tokens (versus 281); removes `for (var i = 0; i < number.length; i++) {`.
- Without L12: 258 tokens (versus 281); removes `var v = number.codeUnitAt(i) - 48;`.
- Without L13: 255 tokens (versus 281); removes `if ((number.length - i) % 2 == 0) {`.
- Without L14: 272 tokens (versus 281); removes `v *= 2;`.
- Without L15: 262 tokens (versus 281); removes `if (v > 9) v -= 9;`.
- Without L16: 277 tokens (versus 281); removes `}`.
- Without L17: 272 tokens (versus 281); removes `sum += v;`.
- Without L18: 278 tokens (versus 281); removes `}`.
- Without L19: 263 tokens (versus 281); removes `if (sum % 10 == 0) {`.
- Without L20: 267 tokens (versus 281); removes `print('$number: valid');`.
- Without L21: 274 tokens (versus 281); removes `} else {`.
- Without L22: 246 tokens (versus 281); removes `final without = sum - (number.codeUnitAt(number.length - 1) - 48);`.
- Without L23: 276 tokens (versus 281); removes `print(`.
- Without L24: 240 tokens (versus 281); removes `'$number: invalid (expected check digit ${(10 - without % 10) % 10})',`.
