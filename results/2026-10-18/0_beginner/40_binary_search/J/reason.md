# Task B selection: 40_binary_search / J

## Common answer requirements

Trace search for 50 using actual array values, initial/inclusive bounds, midpoint and comparison updates; list zero-based probes, stopping bounds and failure-state output; derive complete printed line.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Start lo=0, hi=15. Probe 7 reads31<50, so lo=8; probe11 reads53>50, so hi=10; probe9 reads42<50, so lo=10; probe10 reads47<50, so lo=11. Now lo=11>hi=10 and the inclusive-bound loop stops. No equality assignment ever changes the initial not-found state. Probe recording/printing preserves that order; the full line is `50: probes 7 11 9 10 -> not found` followed by newline. One-based storage implementations explicitly access mid+1 while still recording zero-based mid.

<. floors the midpoint division; _1 is negative one. probes begins empty, and append preserves the examination order.

Source: `main.ijs`. Selected original lines: 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `  values =. 3 8 11 15 19 24 27 31 36 42 47 53 58 64 70 77` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `  for_target. 42 3 77 31 50 1 do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    lo =. 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    hi =. 15` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    found =. _1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    probes =. i.0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    while. lo<:hi do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `      mid =. <.(lo+hi)%2` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `      probes =. probes,mid` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `      if. (mid{values)=target do. found =. mid break.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `      elseif. (mid{values)<target do. lo =. mid+1` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L13: `      else. hi =. mid-1` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L14: `      end.` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `    end.` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L16: `    result =. 'not found'` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `    if. found>:0 do. result =. 'index ',":found end.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `    smoutput (":target),': probes ',(":probes),' -> ',result` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **268 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **288 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 217 tokens (versus 268); removes `values =. 3 8 11 15 19 24 27 31 36 42 47 53 58 64 70 77`.
- Without L3: 244 tokens (versus 268); removes `for_target. 42 3 77 31 50 1 do.`.
- Without L4: 261 tokens (versus 268); removes `lo =. 0`.
- Without L5: 260 tokens (versus 268); removes `hi =. 15`.
- Without L6: 260 tokens (versus 268); removes `found =. _1`.
- Without L7: 260 tokens (versus 268); removes `probes =. i.0`.
- Without L8: 259 tokens (versus 268); removes `while. lo<:hi do.`.
- Without L9: 253 tokens (versus 268); removes `mid =. <.(lo+hi)%2`.
- Without L10: 258 tokens (versus 268); removes `probes =. probes,mid`.
- Without L11: 246 tokens (versus 268); removes `if. (mid{values)=target do. found =. mid break.`.
- Without L12: 246 tokens (versus 268); removes `elseif. (mid{values)<target do. lo =. mid+1`.
- Without L13: 256 tokens (versus 268); removes `else. hi =. mid-1`.
- Without L14: 264 tokens (versus 268); removes `end.`.
- Without L15: 265 tokens (versus 268); removes `end.`.
- Without L16: 257 tokens (versus 268); removes `result =. 'not found'`.
- Without L17: 244 tokens (versus 268); removes `if. found>:0 do. result =. 'index ',":found end.`.
- Without L18: 238 tokens (versus 268); removes `smoutput (":target),': probes ',(":probes),' -> ',result`.
