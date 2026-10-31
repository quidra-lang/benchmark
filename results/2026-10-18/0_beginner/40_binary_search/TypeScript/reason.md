# Task B selection: 40_binary_search / TypeScript

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.



Source: `main.ts`. Selected original lines: 1,2,3,4,5,6,7,8,9,11,12,13,14,15,16. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `const values = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `for (const target of [42, 3, 77, 31, 50, 1]) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `  let lo = 0, hi = values.length - 1, found = -1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `  const probes: number[] = [];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `  while (lo <= hi) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    const mid = Math.floor((lo + hi) / 2);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    probes.push(mid);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    if (values[mid] === target) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `      found = mid;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L12: `    if (values[mid] < target) lo = mid + 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    else hi = mid - 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `  }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `  const result = found >= 0 ? `index ${found}` : "not found";` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `  console.log(`${target}: probes ${probes.join(" ")} -> ${result}`);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **335 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **342 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 265 tokens (versus 335); removes `const values = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77];`.
- Without L2: 300 tokens (versus 335); removes `for (const target of [42, 3, 77, 31, 50, 1]) {`.
- Without L3: 304 tokens (versus 335); removes `let lo = 0, hi = values.length - 1, found = -1;`.
- Without L4: 321 tokens (versus 335); removes `const probes: number[] = [];`.
- Without L5: 322 tokens (versus 335); removes `while (lo <= hi) {`.
- Without L6: 310 tokens (versus 335); removes `const mid = Math.floor((lo + hi) / 2);`.
- Without L7: 326 tokens (versus 335); removes `probes.push(mid);`.
- Without L8: 319 tokens (versus 335); removes `if (values[mid] === target) {`.
- Without L9: 326 tokens (versus 335); removes `found = mid;`.
- Without L11: 332 tokens (versus 335); removes `}`.
- Without L12: 310 tokens (versus 335); removes `if (values[mid] < target) lo = mid + 1;`.
- Without L13: 321 tokens (versus 335); removes `else hi = mid - 1;`.
- Without L14: 332 tokens (versus 335); removes `}`.
- Without L15: 302 tokens (versus 335); removes `const result = found >= 0 ? `index ${found}` : "not found";`.
- Without L16: 300 tokens (versus 335); removes `console.log(`${target}: probes ${probes.join(" ")} -> ${result}`);`.
