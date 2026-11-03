# Task B selection: 45_anagram_groups / Kotlin

## Common answer requirements

Locate group emission and explain suppressing singleton groups after full grouping, preserving word order and first-appearance group order without blank/placeholder lines.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Filter at the completed-group output stage: emit only when its size is at least2, using the same group and word traversal. Keep all input words in grouping; do not alter the anagram signature. Gate the whole output line, including its newline, so a singleton leaves no blank line. Where members are streamed directly rather than first collected, collect/count the matching members using the existing equality predicate before emitting any member or newline; keep the existing used marking/first-appearance traversal.



Source: `main.kt`. Selected original lines: 7. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `    for (group in groups.values) println(group.joinToString(" "))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **27 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **145 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 0 tokens (versus 27); removes `for (group in groups.values) println(group.joinToString(" "))`.
