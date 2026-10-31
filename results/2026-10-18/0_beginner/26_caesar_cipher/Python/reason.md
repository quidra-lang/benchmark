# Task B selection: 26_caesar_cipher / Python

## Common answer requirements

Identify the encryption/decryption shift sites and changes from 3 to 13; explain backward wraparound, independent uppercase/lowercase treatment and unchanged nonletters. Keep the original message and two-line output untouched; unchanged print-only statements need no edit or selection.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Replace the encryption shift 3 with 13. Signed-shift implementations use −13 for decryption; implementations using the positive modulo-26 inverse replace 23 by 13. Leave case-specific alphabet bases, modulo 26, and nonletter passthrough logic intact. The original message and output-only operations require no edits; the changed inverse call continues to consume the ciphertext. ROT13 is its own inverse, so positive 13 is equivalent to backward thirteen modulo 26; an unsigned parameter requires this nonnegative representation. The algorithm evidence, not merely its name, establishes case and nonletter behavior.

The standard string constants define separate ASCII lowercase/uppercase alphabets. Slicing letters[shift:] + letters[:shift] rotates each alphabet; −13 works with Python negative slicing. maketrans/translate changes only mapped characters.

Source: `main.py`. Selected original lines: 4-7,9,13-15. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L4: `def caesar(text, shift):` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    shifted = "".join(` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        letters[shift:] + letters[:shift]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        for letters in (ascii_lowercase, ascii_uppercase)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    return text.translate(str.maketrans(ascii_lowercase + ascii_uppercase, shifted))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `encrypted = caesar(message, 3)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `print(encrypted)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `print(caesar(encrypted, -3))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **111 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **159 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L4: 100 tokens (versus 111); removes `def caesar(text, shift):`.
- Without L5: 100 tokens (versus 111); removes `shifted = "".join(`.
- Without L6: 96 tokens (versus 111); removes `letters[shift:] + letters[:shift]`.
- Without L7: 92 tokens (versus 111); removes `for letters in (ascii_lowercase, ascii_uppercase)`.
- Without L9: 85 tokens (versus 111); removes `return text.translate(str.maketrans(ascii_lowercase + ascii_uppercase, shifted))`.
- Without L13: 99 tokens (versus 111); removes `encrypted = caesar(message, 3)`.
- Without L14: 106 tokens (versus 111); removes `print(encrypted)`.
- Without L15: 99 tokens (versus 111); removes `print(caesar(encrypted, -3))`.
