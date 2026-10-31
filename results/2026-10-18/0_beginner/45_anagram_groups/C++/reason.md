# Task B selection: 45_anagram_groups / C++

## Common answer requirements

Locate group emission and explain suppressing singleton groups after full grouping, preserving word order and first-appearance group order without blank/placeholder lines.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Filter at the completed-group output stage: emit only when its size is at least2, using the same group and word traversal. Keep all input words in grouping; do not alter the anagram signature. Gate the whole output line, including its newline, so a singleton leaves no blank line. Where members are streamed directly rather than first collected, collect/count the matching members using the existing equality predicate before emitting any member or newline; keep the existing used marking/first-appearance traversal.

The stream currently emits a group member and spaces immediately. Delay the entire member/space/newline emission until the match count is known; preserve the used flags and traversal.

Source: `main.cpp`. Selected original lines: 13,14,16,17,20,23,24. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L13: `    for (int i = 0; i < 12; i++)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        if (!used[i]) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `            for (int j = i; j < 12; j++)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `                if (!used[j] && keys[j] == keys[i]) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `                    std::cout << words[j];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `                }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L24: `            std::cout << '\n';` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **134 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **402 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L13: 109 tokens (versus 134); removes `for (int i = 0; i < 12; i++)`.
- Without L14: 120 tokens (versus 134); removes `if (!used[i]) {`.
- Without L16: 107 tokens (versus 134); removes `for (int j = i; j < 12; j++)`.
- Without L17: 104 tokens (versus 134); removes `if (!used[j] && keys[j] == keys[i]) {`.
- Without L20: 117 tokens (versus 134); removes `std::cout << words[j];`.
- Without L23: 128 tokens (versus 134); removes `}`.
- Without L24: 119 tokens (versus 134); removes `std::cout << '\n';`.
