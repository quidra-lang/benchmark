# Task B selection: 49_bracket_balance / Zig

## Common answer requirements

Locate stack representation, opening push/index origin, closing-match/pop dependencies and EOF error assignment; explain tracking original positions and reporting earliest unmatched opener only at clean EOF, preserving immediate mismatch, balanced results and formatting.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Store an original zero-based index alongside each opening bracket (a bracket/index record or synchronized position stack). Push it at the opening event using the existing full-character scan index, including spaces, and remove it when its matching opening is popped. Adapt top comparisons to read the bracket component while preserving the immediate closing-error assignment and break. At clean EOF with a nonempty stack, replace string-length error with the oldest remaining opening position (or minimum stored position). Do not overwrite an earlier closing error. Empty-stack balanced behavior and existing error variable/output formatting remain valid.

A parallel [100]usize position array indexed by len is sufficient; store i beside stack[len] before increment, decrement len for both logically, and use positions[0] at guarded EOF. Keep the err optional unchanged.

Source: `main.zig`. Selected original lines: 17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L17: `        var stack: [100]u8 = undefined;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        var len: usize = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `        var err: ?usize = null;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `        for (s, 0..) |c, i| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `            if (c == '(' or c == '[' or c == '{') {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `                stack[len] = c;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `                len += 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `            } else if (c == ')' or c == ']' or c == '}') {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L25: `                const expected: u8 = if (c == ')') '(' else if (c == ']') '[' else '{';` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L26: `                if (len == 0 or stack[len - 1] != expected) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L27: `                    err = i;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `                    break;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L29: `                }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L30: `                len -= 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L31: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L32: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L33: `        if (err == null and len > 0)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L34: `            err = s.len;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **335 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **741 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L17: 316 tokens (versus 335); removes `var stack: [100]u8 = undefined;`.
- Without L18: 321 tokens (versus 335); removes `var len: usize = 0;`.
- Without L19: 320 tokens (versus 335); removes `var err: ?usize = null;`.
- Without L20: 314 tokens (versus 335); removes `for (s, 0..) |c, i| {`.
- Without L21: 298 tokens (versus 335); removes `if (c == '(' or c == '[' or c == '{') {`.
- Without L22: 321 tokens (versus 335); removes `stack[len] = c;`.
- Without L23: 324 tokens (versus 335); removes `len += 1;`.
- Without L24: 294 tokens (versus 335); removes `} else if (c == ')' or c == ']' or c == '}') {`.
- Without L25: 281 tokens (versus 335); removes `const expected: u8 = if (c == ')') '(' else if (c == ']') '[' else '{';`.
- Without L26: 304 tokens (versus 335); removes `if (len == 0 or stack[len - 1] != expected) {`.
- Without L27: 323 tokens (versus 335); removes `err = i;`.
- Without L28: 327 tokens (versus 335); removes `break;`.
- Without L29: 329 tokens (versus 335); removes `}`.
- Without L30: 324 tokens (versus 335); removes `len -= 1;`.
- Without L31: 330 tokens (versus 335); removes `}`.
- Without L32: 331 tokens (versus 335); removes `}`.
- Without L33: 315 tokens (versus 335); removes `if (err == null and len > 0)`.
- Without L34: 323 tokens (versus 335); removes `err = s.len;`.
