# Task B selection: 26_caesar_cipher / Quidra

## Common answer requirements

Identify the encryption/decryption shift sites and changes from 3 to 13; explain backward wraparound, independent uppercase/lowercase treatment and unchanged nonletters. Keep the original message and two-line output untouched; unchanged print-only statements need no edit or selection.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Replace the encryption shift 3 with 13. Signed-shift implementations use −13 for decryption; implementations using the positive modulo-26 inverse replace 23 by 13. Leave case-specific alphabet bases, modulo 26, and nonletter passthrough logic intact. The original message and output-only operations require no edits; the changed inverse call continues to consume the ciphertext. ROT13 is its own inverse, so positive 13 is equivalent to backward thirteen modulo 26; an unsigned parameter requires this nonnegative representation. The algorithm evidence, not merely its name, establishes case and nonletter behavior.



Source: `main.qui`. Selected original lines: 1-2,4-12,16-17. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `string caesar(string text, int shift)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    string alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    for nat i < len(text)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        match alphabet.find(text[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `            nat position` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `                int index = int(position)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `                int base = if index < 26 then 0 else 26` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `                int shifted = base + (index - base + shift + 26) % 26` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `                result += alphabet[shifted]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            none` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `                result += text[i]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `string encrypted = caesar(message, 3)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `print("{encrypted}{NL}{caesar(encrypted, -3)}{NL}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **210 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **254 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 196 tokens (versus 210); removes `string caesar(string text, int shift)`.
- Without L2: 198 tokens (versus 210); removes `string alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"`.
- Without L4: 196 tokens (versus 210); removes `for nat i < len(text)`.
- Without L5: 196 tokens (versus 210); removes `match alphabet.find(text[i])`.
- Without L6: 203 tokens (versus 210); removes `nat position`.
- Without L7: 195 tokens (versus 210); removes `int index = int(position)`.
- Without L8: 182 tokens (versus 210); removes `int base = if index < 26 then 0 else 26`.
- Without L9: 174 tokens (versus 210); removes `int shifted = base + (index - base + shift + 26) % 26`.
- Without L10: 197 tokens (versus 210); removes `result += alphabet[shifted]`.
- Without L11: 205 tokens (versus 210); removes `none`.
- Without L12: 197 tokens (versus 210); removes `result += text[i]`.
- Without L16: 196 tokens (versus 210); removes `string encrypted = caesar(message, 3)`.
- Without L17: 185 tokens (versus 210); removes `print("{encrypted}{NL}{caesar(encrypted, -3)}{NL}")`.
