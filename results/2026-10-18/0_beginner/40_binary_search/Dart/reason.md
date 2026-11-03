# Task B selection: 40_binary_search / Dart

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.

The nullable found variable begins null by Dart local initialization semantics; equality is the only shown assignment to it. StringBuffer writes are connected to stdout by L24.

Source: `main.dart`. Selected original lines: 5,6,7,8,9,10,11,12,13,14,16,17,18,19,20,21,22,24. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L5: `  const a = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `  for (final target in [42, 3, 77, 31, 50, 1]) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    var lo = 0, hi = 15;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    int? found;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    out.write('$target: probes');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    while (lo <= hi) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `      final mid = (lo + hi) ~/ 2;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `      out.write(' $mid');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `      if (a[mid] == target) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        found = mid;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `      } else if (a[mid] < target) {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `        lo = mid + 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `      } else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L19: `        hi = mid - 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `      }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L21: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L22: `    out.writeln(found == null ? ' -> not found' : ' -> index $found');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `  stdout.write(out);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **328 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **369 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L5: 257 tokens (versus 328); removes `const a = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77];`.
- Without L6: 292 tokens (versus 328); removes `for (final target in [42, 3, 77, 31, 50, 1]) {`.
- Without L7: 310 tokens (versus 328); removes `var lo = 0, hi = 15;`.
- Without L8: 321 tokens (versus 328); removes `int? found;`.
- Without L9: 313 tokens (versus 328); removes `out.write('$target: probes');`.
- Without L10: 315 tokens (versus 328); removes `while (lo <= hi) {`.
- Without L11: 307 tokens (versus 328); removes `final mid = (lo + hi) ~/ 2;`.
- Without L12: 314 tokens (versus 328); removes `out.write(' $mid');`.
- Without L13: 311 tokens (versus 328); removes `if (a[mid] == target) {`.
- Without L14: 319 tokens (versus 328); removes `found = mid;`.
- Without L16: 307 tokens (versus 328); removes `} else if (a[mid] < target) {`.
- Without L17: 315 tokens (versus 328); removes `lo = mid + 1;`.
- Without L18: 320 tokens (versus 328); removes `} else {`.
- Without L19: 315 tokens (versus 328); removes `hi = mid - 1;`.
- Without L20: 324 tokens (versus 328); removes `}`.
- Without L21: 325 tokens (versus 328); removes `}`.
- Without L22: 292 tokens (versus 328); removes `out.writeln(found == null ? ' -> not found' : ' -> index $found');`.
- Without L24: 319 tokens (versus 328); removes `stdout.write(out);`.
