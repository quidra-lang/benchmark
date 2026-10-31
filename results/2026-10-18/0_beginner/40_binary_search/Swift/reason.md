# Task B selection: 40_binary_search / Swift

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.



Source: `main.swift`. Selected original lines: 1,2,3,4,5,6,7,8,10,11,12,13,14. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `let values = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `for target in [42, 3, 77, 31, 50, 1] {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    var lo = 0, hi = 15, found = -1, probes = [Int]()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    while lo <= hi {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        let mid = (lo + hi) / 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        probes.append(mid)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        if values[mid] == target {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `            found = mid` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L11: `        if values[mid] < target { lo = mid + 1 } else { hi = mid - 1 }` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L13: `    let result = found >= 0 ? "index \(found)" : "not found"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    print("\(target): probes \(probes.map(String.init).joined(separator: " ")) -> \(result)")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **325 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **332 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 256 tokens (versus 325); removes `let values = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77]`.
- Without L2: 294 tokens (versus 325); removes `for target in [42, 3, 77, 31, 50, 1] {`.
- Without L3: 289 tokens (versus 325); removes `var lo = 0, hi = 15, found = -1, probes = [Int]()`.
- Without L4: 314 tokens (versus 325); removes `while lo <= hi {`.
- Without L5: 305 tokens (versus 325); removes `let mid = (lo + hi) / 2`.
- Without L6: 316 tokens (versus 325); removes `probes.append(mid)`.
- Without L7: 310 tokens (versus 325); removes `if values[mid] == target {`.
- Without L8: 316 tokens (versus 325); removes `found = mid`.
- Without L10: 321 tokens (versus 325); removes `}`.
- Without L11: 282 tokens (versus 325); removes `if values[mid] < target { lo = mid + 1 } else { hi = mid - 1 }`.
- Without L12: 322 tokens (versus 325); removes `}`.
- Without L13: 293 tokens (versus 325); removes `let result = found >= 0 ? "index \(found)" : "not found"`.
- Without L14: 282 tokens (versus 325); removes `print("\(target): probes \(probes.map(String.init).joined(separator: " ")) -> \(result)")`.
