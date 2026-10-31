# Task B selection: 49_bracket_balance / Python

## Common answer requirements

Locate stack representation, opening push/index origin, closing-match/pop dependencies and EOF error assignment; explain tracking original positions and reporting earliest unmatched opener only at clean EOF, preserving immediate mismatch, balanced results and formatting.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Store an original zero-based index alongside each opening bracket (a bracket/index record or synchronized position stack). Push it at the opening event using the existing full-character scan index, including spaces, and remove it when its matching opening is popped. Adapt top comparisons to read the bracket component while preserving the immediate closing-error assignment and break. At clean EOF with a nonempty stack, replace string-length error with the oldest remaining opening position (or minimum stored position). Do not overwrite an earlier closing error. Empty-stack balanced behavior and existing error variable/output formatting remain valid.



Source: `main.py`. Selected original lines: 12-20,21-23. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L12: `    stack = []` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    error = None` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    for index, char in enumerate(text):` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `        if char in "([{":` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `            stack.append(char)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `        elif char in matching:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `            if not stack or stack[-1] != matching[char]:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `                error = index` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `                break` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `            stack.pop()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `    if error is None and stack:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `        error = len(text)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **140 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **389 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L12: 133 tokens (versus 140); removes `stack = []`.
- Without L13: 133 tokens (versus 140); removes `error = None`.
- Without L14: 124 tokens (versus 140); removes `for index, char in enumerate(text):`.
- Without L15: 125 tokens (versus 140); removes `if char in "([{":`.
- Without L16: 130 tokens (versus 140); removes `stack.append(char)`.
- Without L17: 129 tokens (versus 140); removes `elif char in matching:`.
- Without L18: 116 tokens (versus 140); removes `if not stack or stack[-1] != matching[char]:`.
- Without L19: 130 tokens (versus 140); removes `error = index`.
- Without L20: 134 tokens (versus 140); removes `break`.
- Without L21: 131 tokens (versus 140); removes `stack.pop()`.
- Without L22: 126 tokens (versus 140); removes `if error is None and stack:`.
- Without L23: 129 tokens (versus 140); removes `error = len(text)`.
