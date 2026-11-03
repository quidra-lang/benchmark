# Task B selection: 40_binary_search / PHP

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.



Source: `main.php`. Selected original lines: 3,4,5,6,7,8,9,10,11,12,13,15,16,17,18,19,20,21,22. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `$numbers = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `foreach ([42, 3, 77, 31, 50, 1] as $target) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    $lo = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    $hi = count($numbers) - 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    $found = -1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    $probes = [];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    while ($lo <= $hi) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        $mid = intdiv($lo + $hi, 2);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        $probes[] = $mid;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        if ($numbers[$mid] === $target) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            $found = $mid;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `        } elseif ($numbers[$mid] < $target) {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L16: `            $lo = $mid + 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `        } else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L18: `            $hi = $mid - 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L20: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L21: `    $result = $found >= 0 ? 'index ' . $found : 'not found';` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `    printf("%d: probes %s -> %s\n", $target, implode(' ', $probes), $result);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **374 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **387 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 305 tokens (versus 374); removes `$numbers = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77];`.
- Without L4: 340 tokens (versus 374); removes `foreach ([42, 3, 77, 31, 50, 1] as $target) {`.
- Without L5: 365 tokens (versus 374); removes `$lo = 0;`.
- Without L6: 357 tokens (versus 374); removes `$hi = count($numbers) - 1;`.
- Without L7: 364 tokens (versus 374); removes `$found = -1;`.
- Without L8: 365 tokens (versus 374); removes `$probes = [];`.
- Without L9: 359 tokens (versus 374); removes `while ($lo <= $hi) {`.
- Without L10: 352 tokens (versus 374); removes `$mid = intdiv($lo + $hi, 2);`.
- Without L11: 362 tokens (versus 374); removes `$probes[] = $mid;`.
- Without L12: 354 tokens (versus 374); removes `if ($numbers[$mid] === $target) {`.
- Without L13: 362 tokens (versus 374); removes `$found = $mid;`.
- Without L15: 352 tokens (versus 374); removes `} elseif ($numbers[$mid] < $target) {`.
- Without L16: 358 tokens (versus 374); removes `$lo = $mid + 1;`.
- Without L17: 366 tokens (versus 374); removes `} else {`.
- Without L18: 358 tokens (versus 374); removes `$hi = $mid - 1;`.
- Without L19: 370 tokens (versus 374); removes `}`.
- Without L20: 371 tokens (versus 374); removes `}`.
- Without L21: 340 tokens (versus 374); removes `$result = $found >= 0 ? 'index ' . $found : 'not found';`.
- Without L22: 332 tokens (versus 374); removes `printf("%d: probes %s -> %s\n", $target, implode(' ', $probes), $result);`.
