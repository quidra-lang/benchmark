# Task B selection: 26_caesar_cipher / Rust

## Common answer requirements

Identify the encryption/decryption shift sites and changes from 3 to 13; explain backward wraparound, independent uppercase/lowercase treatment and unchanged nonletters. Keep the original message and two-line output untouched; unchanged print-only statements need no edit or selection.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Replace the encryption shift 3 with 13. Signed-shift implementations use −13 for decryption; implementations using the positive modulo-26 inverse replace 23 by 13. Leave case-specific alphabet bases, modulo 26, and nonletter passthrough logic intact. The original message and output-only operations require no edits; the changed inverse call continues to consume the ciphertext. ROT13 is its own inverse, so positive 13 is equivalent to backward thirteen modulo 26; an unsigned parameter requires this nonnegative representation. The algorithm evidence, not merely its name, establishes case and nonletter behavior.



Source: `main.rs`. Selected original lines: 1-9,11,18,20. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `fn cipher(s: &str, shift: u8) -> String {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    s.bytes()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `        .map(|c| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `            let base = if c.is_ascii_lowercase() {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `                b'a'` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `            } else if c.is_ascii_uppercase() {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L7: `                b'A'` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `            } else {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L9: `                return c as char;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            (base + (c - base + shift) % 26) as char` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `    let encrypted = cipher(message, 3);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `    println!("{}", cipher(&encrypted, 23));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **192 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **267 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 170 tokens (versus 192); removes `fn cipher(s: &str, shift: u8) -> String {`.
- Without L2: 185 tokens (versus 192); removes `s.bytes()`.
- Without L3: 181 tokens (versus 192); removes `.map(|c| {`.
- Without L4: 169 tokens (versus 192); removes `let base = if c.is_ascii_lowercase() {`.
- Without L5: 183 tokens (versus 192); removes `b'a'`.
- Without L6: 171 tokens (versus 192); removes `} else if c.is_ascii_uppercase() {`.
- Without L7: 183 tokens (versus 192); removes `b'A'`.
- Without L8: 183 tokens (versus 192); removes `} else {`.
- Without L9: 179 tokens (versus 192); removes `return c as char;`.
- Without L11: 162 tokens (versus 192); removes `(base + (c - base + shift) % 26) as char`.
- Without L18: 176 tokens (versus 192); removes `let encrypted = cipher(message, 3);`.
- Without L20: 170 tokens (versus 192); removes `println!("{}", cipher(&encrypted, 23));`.
