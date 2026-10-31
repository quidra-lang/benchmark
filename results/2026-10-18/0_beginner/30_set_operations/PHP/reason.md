# Task B selection: 30_set_operations / PHP

## Common answer requirements

Locate the A-minus-B difference construction and explain reversing its operands/predicate only; preserve third-line label/position, uniqueness and ascending order, and all other operations. Unaffected formatting and input data need no change.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Reverse the difference operands: B minus A, or membership in B and not in A. Change only the difference expression/predicate (and, for a mutable copied result, copy B then remove A). Keep the existing label, result slot, ordering/deduplication pipeline, and independent union/intersection/symmetric-difference expressions. Do not globally exchange A and B or replace the A-minus-B term used inside a symmetric difference.



Source: `main.php`. Selected original lines: 8. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L8: `    array_diff($a, $b),` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **14 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **275 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L8: 0 tokens (versus 14); removes `array_diff($a, $b),`.
