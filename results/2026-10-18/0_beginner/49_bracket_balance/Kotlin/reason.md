# Task B selection: 49_bracket_balance / Kotlin

## Common answer requirements

Locate stack representation, opening push/index origin, closing-match/pop dependencies and EOF error assignment; explain tracking original positions and reporting earliest unmatched opener only at clean EOF, preserving immediate mismatch, balanced results and formatting.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Store an original zero-based index alongside each opening bracket (a bracket/index record or synchronized position stack). Push it at the opening event using the existing full-character scan index, including spaces, and remove it when its matching opening is popped. Adapt top comparisons to read the bracket component while preserving the immediate closing-error assignment and break. At clean EOF with a nonempty stack, replace string-length error with the oldest remaining opening position (or minimum stored position). Do not overwrite an earlier closing error. Empty-stack balanced behavior and existing error variable/output formatting remain valid.



Source: `main.kt`. Selected original lines: 7,8,9,10,11,12,13,14,15,16,17,18,19,20,21. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `        val stack = ArrayDeque<Char>()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        var error = -1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        for ((i, ch) in text.withIndex()) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `            val close = ")]}".indexOf(ch)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            if (ch in "([{") {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `                stack.add(ch)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            } else if (close >= 0) {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L14: `                if (stack.isEmpty() || stack.last() != "([{"[close]) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `                    error = i` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `                    break` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `                }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L18: `                stack.removeLast()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L20: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L21: `        if (error < 0 && stack.isNotEmpty()) error = text.length` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **231 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **460 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 215 tokens (versus 231); removes `val stack = ArrayDeque<Char>()`.
- Without L8: 220 tokens (versus 231); removes `var error = -1`.
- Without L9: 207 tokens (versus 231); removes `for ((i, ch) in text.withIndex()) {`.
- Without L10: 210 tokens (versus 231); removes `val close = ")]}".indexOf(ch)`.
- Without L11: 212 tokens (versus 231); removes `if (ch in "([{") {`.
- Without L12: 220 tokens (versus 231); removes `stack.add(ch)`.
- Without L13: 212 tokens (versus 231); removes `} else if (close >= 0) {`.
- Without L14: 195 tokens (versus 231); removes `if (stack.isEmpty() || stack.last() != "([{"[close]) {`.
- Without L15: 220 tokens (versus 231); removes `error = i`.
- Without L16: 224 tokens (versus 231); removes `break`.
- Without L17: 225 tokens (versus 231); removes `}`.
- Without L18: 220 tokens (versus 231); removes `stack.removeLast()`.
- Without L19: 226 tokens (versus 231); removes `}`.
- Without L20: 227 tokens (versus 231); removes `}`.
- Without L21: 201 tokens (versus 231); removes `if (error < 0 && stack.isNotEmpty()) error = text.length`.
