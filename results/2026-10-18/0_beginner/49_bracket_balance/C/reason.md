# Task B selection: 49_bracket_balance / C

## Common answer requirements

Locate stack representation, opening push/index origin, closing-match/pop dependencies and EOF error assignment; explain tracking original positions and reporting earliest unmatched opener only at clean EOF, preserving immediate mismatch, balanced results and formatting.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Store an original zero-based index alongside each opening bracket (a bracket/index record or synchronized position stack). Push it at the opening event using the existing full-character scan index, including spaces, and remove it when its matching opening is popped. Adapt top comparisons to read the bracket component while preserving the immediate closing-error assignment and break. At clean EOF with a nonempty stack, replace string-length error with the oldest remaining opening position (or minimum stored position). Do not overwrite an earlier closing error. Empty-stack balanced behavior and existing error variable/output formatting remain valid.

Add a parallel original-index array (or change stack element representation). stack[0] is the earliest live opener; top-- must pop its position in lockstep. Keep error<0 in the EOF guard.

Source: `main.c`. Selected original lines: 9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L9: `        char stack[128];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        int top = 0, error = -1, len = (int)strlen(s);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        for (int i = 0; i < len; i++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `            char c = s[i];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            if (c == '(' || c == '[' || c == '{') {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `                stack[top++] = c;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `            } else if (c == ')' || c == ']' || c == '}') {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L16: `                char expected = c == ')' ? '(' : c == ']' ? '[' : '{';` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `                if (!top || stack[top - 1] != expected) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `                    error = i;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `                    break;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `                }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L21: `                top--;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `            }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L23: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L24: `        if (error < 0 && top)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L25: `            error = len;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **323 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **629 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L9: 311 tokens (versus 323); removes `char stack[128];`.
- Without L10: 291 tokens (versus 323); removes `int top = 0, error = -1, len = (int)strlen(s);`.
- Without L11: 296 tokens (versus 323); removes `for (int i = 0; i < len; i++) {`.
- Without L12: 308 tokens (versus 323); removes `char c = s[i];`.
- Without L13: 286 tokens (versus 323); removes `if (c == '(' || c == '[' || c == '{') {`.
- Without L14: 308 tokens (versus 323); removes `stack[top++] = c;`.
- Without L15: 282 tokens (versus 323); removes `} else if (c == ')' || c == ']' || c == '}') {`.
- Without L16: 276 tokens (versus 323); removes `char expected = c == ')' ? '(' : c == ']' ? '[' : '{';`.
- Without L17: 295 tokens (versus 323); removes `if (!top || stack[top - 1] != expected) {`.
- Without L18: 311 tokens (versus 323); removes `error = i;`.
- Without L19: 315 tokens (versus 323); removes `break;`.
- Without L20: 317 tokens (versus 323); removes `}`.
- Without L21: 315 tokens (versus 323); removes `top--;`.
- Without L22: 318 tokens (versus 323); removes `}`.
- Without L23: 319 tokens (versus 323); removes `}`.
- Without L24: 307 tokens (versus 323); removes `if (error < 0 && top)`.
- Without L25: 313 tokens (versus 323); removes `error = len;`.
