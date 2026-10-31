# Task B selection: 49_bracket_balance / Quidra

## Common answer requirements

Locate stack representation, opening push/index origin, closing-match/pop dependencies and EOF error assignment; explain tracking original positions and reporting earliest unmatched opener only at clean EOF, preserving immediate mismatch, balanced results and formatting.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Store an original zero-based index alongside each opening bracket (a bracket/index record or synchronized position stack). Push it at the opening event using the existing full-character scan index, including spaces, and remove it when its matching opening is popped. Adapt top comparisons to read the bracket component while preserving the immediate closing-error assignment and break. At clean EOF with a nonempty stack, replace string-length error with the oldest remaining opening position (or minimum stored position). Do not overwrite an earlier closing error. Empty-stack balanced behavior and existing error variable/output formatting remain valid.

The current string stack needs a synchronized int[] of original int(i) indices or a record-array replacement. Slice off its final index together with the final bracket. failure==-1 remains essential before substituting the earliest stored index.

Source: `main.qui`. Selected original lines: 8-20,23-24. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L8: `    string stack = ""` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    int failure = -1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    for nat i < len(text)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        string character = text[i]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        if openings.contains(character)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            stack += character` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        else` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `            match closings.find(character)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `                nat position` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `                    if len(stack) == 0 or stack[len(stack) - 1] != openings[position]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `                        failure = int(i)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `                        break` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `                    stack = stack[:<len(stack) - 1]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `    if failure == -1 and len(stack) > 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `        failure = int(len(text))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **208 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **476 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L8: 198 tokens (versus 208); removes `string stack = ""`.
- Without L9: 198 tokens (versus 208); removes `int failure = -1`.
- Without L10: 194 tokens (versus 208); removes `for nat i < len(text)`.
- Without L11: 195 tokens (versus 208); removes `string character = text[i]`.
- Without L12: 197 tokens (versus 208); removes `if openings.contains(character)`.
- Without L13: 199 tokens (versus 208); removes `stack += character`.
- Without L14: 204 tokens (versus 208); removes `else`.
- Without L15: 196 tokens (versus 208); removes `match closings.find(character)`.
- Without L16: 200 tokens (versus 208); removes `nat position`.
- Without L17: 171 tokens (versus 208); removes `if len(stack) == 0 or stack[len(stack) - 1] != openings[position]`.
- Without L18: 193 tokens (versus 208); removes `failure = int(i)`.
- Without L19: 200 tokens (versus 208); removes `break`.
- Without L20: 186 tokens (versus 208); removes `stack = stack[:<len(stack) - 1]`.
- Without L23: 187 tokens (versus 208); removes `if failure == -1 and len(stack) > 0`.
- Without L24: 194 tokens (versus 208); removes `failure = int(len(text))`.
