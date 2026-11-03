# Task B selection: 26_caesar_cipher / Quidra

## Answer and source dependencies

Change the encryption call's shift from 3 to 13 and the decryption call's shift from -3 to -13. The offset normalization converts a signed shift to 0..25; -13 and 13 both normalize to 13. Each alphabet is rotated independently, so lowercase characters map only to lowercase and uppercase only to uppercase, with wraparound within each 26-letter alphabet. Translation replaces the matching letters simultaneously and preserves unmatched spaces and punctuation. Keep the original message and the ciphertext-then-decrypted output structure.

## Selected evidence

Source: `main.qui`. Complete main.qui source lines: 3, 4, 5, 6, 7, 8, 11, 12.
Every selected line is a complete verbatim source line in source order.

The function signature and normalization show signed-shift behavior. The two alphabets and the rotated replacement show independent case-preserving wraparound. The translation call establishes nonletter passthrough using the documented standard-library semantics. The two call sites identify the required edits and the decryption input; the final complete line also contains the output operation.

## Semantics and minimization

Imports and the unchanged message declaration do not establish another answer dependency, so they are omitted. Standard library operations use their documented meanings; their implementations need not be included. Selected evidence fragments need not compile independently. This is a dependency-based selection, not a claim of globally minimal token count.
