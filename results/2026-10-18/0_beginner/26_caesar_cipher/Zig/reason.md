# Task B selection: 26_caesar_cipher / Zig

## Common answer requirements

Identify the encryption/decryption shift sites and changes from 3 to 13; explain backward wraparound, independent uppercase/lowercase treatment and unchanged nonletters. Keep the original message and two-line output untouched; unchanged print-only statements need no edit or selection.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Replace the encryption shift 3 with 13. Signed-shift implementations use −13 for decryption; implementations using the positive modulo-26 inverse replace 23 by 13. Leave case-specific alphabet bases, modulo 26, and nonletter passthrough logic intact. The original message and output-only operations require no edits; the changed inverse call continues to consume the ciphertext. ROT13 is its own inverse, so positive 13 is equivalent to backward thirteen modulo 26; an unsigned parameter requires this nonnegative representation. The algorithm evidence, not merely its name, establishes case and nonletter behavior.



Source: `main.zig`. Selected original lines: 3-5,15-18. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `fn shift(c: u8, amount: u8) u8 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    const base: u8 = if (c >= 'a' and c <= 'z') 'a' else if (c >= 'A' and c <= 'Z') 'A' else return c;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    return base + (c - base + amount) % 26;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `    for (message, 0..) |c, i|` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `        cipher[i] = shift(c, 3);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `    for (cipher, 0..) |c, i|` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        plain[i] = shift(c, 23);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **189 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **406 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 169 tokens (versus 189); removes `fn shift(c: u8, amount: u8) u8 {`.
- Without L4: 118 tokens (versus 189); removes `const base: u8 = if (c >= 'a' and c <= 'z') 'a' else if (c >= 'A' and c <= 'Z') 'A' else return c;`.
- Without L5: 164 tokens (versus 189); removes `return base + (c - base + amount) % 26;`.
- Without L15: 171 tokens (versus 189); removes `for (message, 0..) |c, i|`.
- Without L16: 171 tokens (versus 189); removes `cipher[i] = shift(c, 3);`.
- Without L17: 171 tokens (versus 189); removes `for (cipher, 0..) |c, i|`.
- Without L18: 170 tokens (versus 189); removes `plain[i] = shift(c, 23);`.
