# Task B selection: 49_bracket_balance / Lua

## Common answer requirements

Locate stack representation, opening push/index origin, closing-match/pop dependencies and EOF error assignment; explain tracking original positions and reporting earliest unmatched opener only at clean EOF, preserving immediate mismatch, balanced results and formatting.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Store an original zero-based index alongside each opening bracket (a bracket/index record or synchronized position stack). Push it at the opening event using the existing full-character scan index, including spaces, and remove it when its matching opening is popped. Adapt top comparisons to read the bracket component while preserving the immediate closing-error assignment and break. At clean EOF with a nonempty stack, replace string-length error with the oldest remaining opening position (or minimum stored position). Do not overwrite an earlier closing error. Empty-stack balanced behavior and existing error variable/output formatting remain valid.

Store position−1, matching the closing-error conversion; table.remove(stack) pops the last opening and position together. The first remaining entry is the oldest.

Source: `main.lua`. Selected original lines: 7,8,9,10,11,12,13,14,15,16,17,18,19,20. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `    local stack, error_index = {}, -1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    for position = 1, #text do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        local c = text:sub(position, position)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        if matching[c] then` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            stack[#stack + 1] = c` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        elseif c == ")" or c == "]" or c == "}" then` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            if #stack == 0 or matching[stack[#stack]] ~= c then` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `                error_index = position - 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `                break` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `            end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `            table.remove(stack)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L19: `    end` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L20: `    if error_index < 0 and #stack > 0 then error_index = #text end` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **219 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **495 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 200 tokens (versus 219); removes `local stack, error_index = {}, -1`.
- Without L8: 204 tokens (versus 219); removes `for position = 1, #text do`.
- Without L9: 201 tokens (versus 219); removes `local c = text:sub(position, position)`.
- Without L10: 208 tokens (versus 219); removes `if matching[c] then`.
- Without L11: 202 tokens (versus 219); removes `stack[#stack + 1] = c`.
- Without L12: 185 tokens (versus 219); removes `elseif c == ")" or c == "]" or c == "}" then`.
- Without L13: 191 tokens (versus 219); removes `if #stack == 0 or matching[stack[#stack]] ~= c then`.
- Without L14: 203 tokens (versus 219); removes `error_index = position - 1`.
- Without L15: 213 tokens (versus 219); removes `break`.
- Without L16: 214 tokens (versus 219); removes `end`.
- Without L17: 209 tokens (versus 219); removes `table.remove(stack)`.
- Without L18: 215 tokens (versus 219); removes `end`.
- Without L19: 216 tokens (versus 219); removes `end`.
- Without L20: 186 tokens (versus 219); removes `if error_index < 0 and #stack > 0 then error_index = #text end`.
