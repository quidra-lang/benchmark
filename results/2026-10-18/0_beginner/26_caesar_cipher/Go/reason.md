# Task B selection: 26_caesar_cipher / Go

## Common answer requirements

Identify the encryption/decryption shift sites and changes from 3 to 13; explain backward wraparound, independent uppercase/lowercase treatment and unchanged nonletters. Keep the original message and two-line output untouched; unchanged print-only statements need no edit or selection.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Replace the encryption shift 3 with 13. Signed-shift implementations use −13 for decryption; implementations using the positive modulo-26 inverse replace 23 by 13. Leave case-specific alphabet bases, modulo 26, and nonletter passthrough logic intact. The original message and output-only operations require no edits; the changed inverse call continues to consume the ciphertext. ROT13 is its own inverse, so positive 13 is equivalent to backward thirteen modulo 26; an unsigned parameter requires this nonnegative representation. The algorithm evidence, not merely its name, establishes case and nonletter behavior.



Source: `main.go`. Selected original lines: 5-11,14,19,21. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L5: `func cipher(s string, shift byte) string {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `	out := []byte(s)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `	for i, c := range out {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `		if c >= 'a' && c <= 'z' {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `			out[i] = 'a' + (c-'a'+shift)%26` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `		} else if c >= 'A' && c <= 'Z' {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L11: `			out[i] = 'A' + (c-'A'+shift)%26` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `	return string(out)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `	encrypted := cipher(message, 3)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `	fmt.Println(cipher(encrypted, 23))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **191 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **258 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L5: 173 tokens (versus 191); removes `func cipher(s string, shift byte) string {`.
- Without L6: 180 tokens (versus 191); removes `out := []byte(s)`.
- Without L7: 175 tokens (versus 191); removes `for i, c := range out {`.
- Without L8: 167 tokens (versus 191); removes `if c >= 'a' && c <= 'z' {`.
- Without L9: 162 tokens (versus 191); removes `out[i] = 'a' + (c-'a'+shift)%26`.
- Without L10: 163 tokens (versus 191); removes `} else if c >= 'A' && c <= 'Z' {`.
- Without L11: 162 tokens (versus 191); removes `out[i] = 'A' + (c-'A'+shift)%26`.
- Without L14: 183 tokens (versus 191); removes `return string(out)`.
- Without L19: 178 tokens (versus 191); removes `encrypted := cipher(message, 3)`.
- Without L21: 176 tokens (versus 191); removes `fmt.Println(cipher(encrypted, 23))`.
