# Task B selection: 38_insertion_sort_steps / J

## Common answer requirements

Locate the insertion-sort comparison controlling shifts; explain decreasing order and stability by shifting strictly smaller preceding values, without altering positions, shift accounting, insertion, input or output.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Reverse the strict comparison from preceding-value > inserted-value to preceding-value < inserted-value. Keep the index-bound guard and the existing right-shift operation. Equal values then do not shift past the new value, so their prior order is preserved; using <= would break that stability. The loop range, saved insertion value, insertion assignment, shift counters, and reporting need no changes. In J the equivalent early-break predicate changes from preceding <= value to preceding >= value, leaving only strictly smaller values to reach the shift.

L8 retains the nonnegative index guard, L9 is the early-stop condition to reverse, and L10 establishes that falling through moves the old value to j+1. <:/ >: are inclusive comparisons in J, so the break must remain inclusive to keep equality stationary.

Source: `main.ijs`. Selected original lines: 8-10. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L8: `    while. j>:0 do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `      if. (j{values)<:value do. break. end.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `      values =. (j{values) (j+1)}values` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **47 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **235 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L8: 38 tokens (versus 47); removes `while. j>:0 do.`.
- Without L9: 29 tokens (versus 47); removes `if. (j{values)<:value do. break. end.`.
- Without L10: 27 tokens (versus 47); removes `values =. (j{values) (j+1)}values`.
