# Task B selection: 43_run_length_encoding / Go

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.



Source: `main.go`. Selected original lines: 9,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L9: `	for _, s := range []string{"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `		encoded := ""` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `		for i := 0; i < len(s); {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `			j := i + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `			for j < len(s) && s[j] == s[i] {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `				j++` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `			}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `			encoded += fmt.Sprintf("%d%c", j-i, s[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `			i = j` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `		}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L20: `		decoded := ""` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `		for i := 0; i < len(encoded); {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `			count := 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `			for encoded[i] >= '0' && encoded[i] <= '9' {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `				count = count*10 + int(encoded[i]-'0')` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L25: `				i++` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L26: `			}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L27: `			decoded += strings.Repeat(string(encoded[i]), count)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `			i++` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L29: `		}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.

## Minimization and semantics

The selected excerpt measures **307 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **384 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L9: 272 tokens (versus 307); removes `for _, s := range []string{"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",`.
- Without L11: 298 tokens (versus 307); removes `encoded := ""`.
- Without L12: 284 tokens (versus 307); removes `for i := 0; i < len(s); {`.
- Without L13: 294 tokens (versus 307); removes `j := i + 1`.
- Without L14: 277 tokens (versus 307); removes `for j < len(s) && s[j] == s[i] {`.
- Without L15: 300 tokens (versus 307); removes `j++`.
- Without L16: 302 tokens (versus 307); removes `}`.
- Without L17: 279 tokens (versus 307); removes `encoded += fmt.Sprintf("%d%c", j-i, s[i])`.
- Without L18: 298 tokens (versus 307); removes `i = j`.
- Without L19: 303 tokens (versus 307); removes `}`.
- Without L20: 298 tokens (versus 307); removes `decoded := ""`.
- Without L21: 284 tokens (versus 307); removes `for i := 0; i < len(encoded); {`.
- Without L22: 298 tokens (versus 307); removes `count := 0`.
- Without L23: 276 tokens (versus 307); removes `for encoded[i] >= '0' && encoded[i] <= '9' {`.
- Without L24: 280 tokens (versus 307); removes `count = count*10 + int(encoded[i]-'0')`.
- Without L25: 300 tokens (versus 307); removes `i++`.
- Without L26: 302 tokens (versus 307); removes `}`.
- Without L27: 284 tokens (versus 307); removes `decoded += strings.Repeat(string(encoded[i]), count)`.
- Without L28: 301 tokens (versus 307); removes `i++`.
- Without L29: 303 tokens (versus 307); removes `}`.
