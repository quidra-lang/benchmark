# Task B selection: 40_binary_search / Go

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.



Source: `main.go`. Selected original lines: 6,7,8,9,10,11,12,13,14,16,17,18,19,20,21,22,23,25,26. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L6: `	a := []int{3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `	for _, t := range []int{42, 3, 77, 31, 50, 1} {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `		lo, hi, found := 0, 15, -1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `		fmt.Printf("%d: probes", t)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `		for lo <= hi {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `			mid := (lo + hi) / 2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `			fmt.Printf(" %d", mid)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `			if a[mid] == t {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `				found = mid` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `			}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `			if a[mid] < t {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `				lo = mid + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `			} else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L20: `				hi = mid - 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `			}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L22: `		}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L23: `		if found >= 0 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L25: `		} else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L26: `			fmt.Println(" -> not found")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **326 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **384 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L6: 256 tokens (versus 326); removes `a := []int{3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77}`.
- Without L7: 287 tokens (versus 326); removes `for _, t := range []int{42, 3, 77, 31, 50, 1} {`.
- Without L8: 304 tokens (versus 326); removes `lo, hi, found := 0, 15, -1`.
- Without L9: 309 tokens (versus 326); removes `fmt.Printf("%d: probes", t)`.
- Without L10: 314 tokens (versus 326); removes `for lo <= hi {`.
- Without L11: 307 tokens (versus 326); removes `mid := (lo + hi) / 2`.
- Without L12: 309 tokens (versus 326); removes `fmt.Printf(" %d", mid)`.
- Without L13: 310 tokens (versus 326); removes `if a[mid] == t {`.
- Without L14: 316 tokens (versus 326); removes `found = mid`.
- Without L16: 321 tokens (versus 326); removes `}`.
- Without L17: 310 tokens (versus 326); removes `if a[mid] < t {`.
- Without L18: 312 tokens (versus 326); removes `lo = mid + 1`.
- Without L19: 317 tokens (versus 326); removes `} else {`.
- Without L20: 312 tokens (versus 326); removes `hi = mid - 1`.
- Without L21: 321 tokens (versus 326); removes `}`.
- Without L22: 322 tokens (versus 326); removes `}`.
- Without L23: 314 tokens (versus 326); removes `if found >= 0 {`.
- Without L25: 318 tokens (versus 326); removes `} else {`.
- Without L26: 309 tokens (versus 326); removes `fmt.Println(" -> not found")`.
