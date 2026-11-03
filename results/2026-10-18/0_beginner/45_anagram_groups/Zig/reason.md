# Task B selection: 45_anagram_groups / Zig

## Common answer requirements

Locate group emission and explain suppressing singleton groups after full grouping, preserving word order and first-appearance group order without blank/placeholder lines.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Filter at the completed-group output stage: emit only when its size is at least2, using the same group and word traversal. Keep all input words in grouping; do not alter the anagram signature. Gate the whole output line, including its newline, so a singleton leaves no blank line. Where members are streamed directly rather than first collected, collect/count the matching members using the existing equality predicate before emitting any member or newline; keep the existing used marking/first-appearance traversal.

Output is currently interleaved with membership selection and used marking. Count/buffer matches first, then gate both member output and final newline; preserve marking and input-order loops.

Source: `main.zig`. Selected original lines: 18,19,20,22,23,26,29,30,31. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L18: `    for (words, 0..) |_, i| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `        if (used[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `            continue;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `        for (i..words.len) |j| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `            if (std.mem.eql(u32, &keys[i], &keys[j])) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L26: `                try out.writeAll(words[j]);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L29: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L30: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L31: `        try out.writeByte('\n');` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **130 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **512 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L18: 110 tokens (versus 130); removes `for (words, 0..) |_, i| {`.
- Without L19: 119 tokens (versus 130); removes `if (used[i])`.
- Without L20: 124 tokens (versus 130); removes `continue;`.
- Without L22: 112 tokens (versus 130); removes `for (i..words.len) |j| {`.
- Without L23: 98 tokens (versus 130); removes `if (std.mem.eql(u32, &keys[i], &keys[j])) {`.
- Without L26: 112 tokens (versus 130); removes `try out.writeAll(words[j]);`.
- Without L29: 125 tokens (versus 130); removes `}`.
- Without L30: 126 tokens (versus 130); removes `}`.
- Without L31: 114 tokens (versus 130); removes `try out.writeByte('\n');`.
