# Task B selection: 40_binary_search / R

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.

The array lookup adds one, while probes and displayed indices remain zero-based.

Source: `main.R`. Selected original lines: 1,2,3,4,5,6,7,8,9,10,11,13,14,15,16,17,18,19,20. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `numbers <- c(3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `for (target in c(42, 3, 77, 31, 50, 1)) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `  lo <- 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `  hi <- length(numbers) - 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `  found <- -1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `  probes <- numeric(0)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `  while (lo <= hi) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    mid <- (lo + hi) %/% 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    probes <- c(probes, mid)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    if (numbers[mid + 1] == target) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `      found <- mid` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    } else if (numbers[mid + 1] < target) {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L14: `      lo <- mid + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `    } else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L16: `      hi <- mid - 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L18: `  }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L19: `  result <- if (found >= 0) sprintf("index %d", found) else "not found"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `  cat(sprintf("%d: probes %s -> %s\n", target, paste(probes, collapse = " "), result))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **354 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **360 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 286 tokens (versus 354); removes `numbers <- c(3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77)`.
- Without L2: 320 tokens (versus 354); removes `for (target in c(42, 3, 77, 31, 50, 1)) {`.
- Without L3: 347 tokens (versus 354); removes `lo <- 0`.
- Without L4: 340 tokens (versus 354); removes `hi <- length(numbers) - 1`.
- Without L5: 346 tokens (versus 354); removes `found <- -1`.
- Without L6: 344 tokens (versus 354); removes `probes <- numeric(0)`.
- Without L7: 341 tokens (versus 354); removes `while (lo <= hi) {`.
- Without L8: 337 tokens (versus 354); removes `mid <- (lo + hi) %/% 2`.
- Without L9: 341 tokens (versus 354); removes `probes <- c(probes, mid)`.
- Without L10: 334 tokens (versus 354); removes `if (numbers[mid + 1] == target) {`.
- Without L11: 346 tokens (versus 354); removes `found <- mid`.
- Without L13: 330 tokens (versus 354); removes `} else if (numbers[mid + 1] < target) {`.
- Without L14: 342 tokens (versus 354); removes `lo <- mid + 1`.
- Without L15: 347 tokens (versus 354); removes `} else {`.
- Without L16: 342 tokens (versus 354); removes `hi <- mid - 1`.
- Without L17: 351 tokens (versus 354); removes `}`.
- Without L18: 351 tokens (versus 354); removes `}`.
- Without L19: 318 tokens (versus 354); removes `result <- if (found >= 0) sprintf("index %d", found) else "not found"`.
- Without L20: 309 tokens (versus 354); removes `cat(sprintf("%d: probes %s -> %s\n", target, paste(probes, collapse = " "), result))`.
