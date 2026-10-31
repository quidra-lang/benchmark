# Task B selection: 40_binary_search / Quidra

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.



Source: `main.qui`. Selected original lines: 1-12,14-18,20-21. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `int[] values = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `int[] targets = [42, 3, 77, 31, 50, 1]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `for int target = targets[]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    int lo = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    int hi = 15` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    int found = -1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    print("{target}: probes")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    while lo <= hi` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        int mid = (lo + hi) / 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        print(" {mid}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        if values[mid] == target` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `            found = mid` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        elif values[mid] < target` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `            lo = mid + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `        else` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `            hi = mid - 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `    if found >= 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `    else` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `        print(" -> not found{NL}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **287 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **311 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 217 tokens (versus 287); removes `int[] values = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77]`.
- Without L2: 257 tokens (versus 287); removes `int[] targets = [42, 3, 77, 31, 50, 1]`.
- Without L3: 276 tokens (versus 287); removes `for int target = targets[]`.
- Without L4: 278 tokens (versus 287); removes `int lo = 0`.
- Without L5: 277 tokens (versus 287); removes `int hi = 15`.
- Without L6: 277 tokens (versus 287); removes `int found = -1`.
- Without L7: 275 tokens (versus 287); removes `print("{target}: probes")`.
- Without L8: 278 tokens (versus 287); removes `while lo <= hi`.
- Without L9: 267 tokens (versus 287); removes `int mid = (lo + hi) / 2`.
- Without L10: 275 tokens (versus 287); removes `print(" {mid}")`.
- Without L11: 274 tokens (versus 287); removes `if values[mid] == target`.
- Without L12: 278 tokens (versus 287); removes `found = mid`.
- Without L14: 274 tokens (versus 287); removes `elif values[mid] < target`.
- Without L15: 274 tokens (versus 287); removes `lo = mid + 1`.
- Without L16: 283 tokens (versus 287); removes `else`.
- Without L17: 274 tokens (versus 287); removes `hi = mid - 1`.
- Without L18: 278 tokens (versus 287); removes `if found >= 0`.
- Without L20: 284 tokens (versus 287); removes `else`.
- Without L21: 270 tokens (versus 287); removes `print(" -> not found{NL}")`.
