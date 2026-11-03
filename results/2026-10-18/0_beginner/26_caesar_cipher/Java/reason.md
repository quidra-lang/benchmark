# Task B selection: 26_caesar_cipher / Java

## Common answer requirements

Identify the encryption/decryption shift sites and changes from 3 to 13; explain backward wraparound, independent uppercase/lowercase treatment and unchanged nonletters. Keep the original message and two-line output untouched; unchanged print-only statements need no edit or selection.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Replace the encryption shift 3 with 13. Signed-shift implementations use −13 for decryption; implementations using the positive modulo-26 inverse replace 23 by 13. Leave case-specific alphabet bases, modulo 26, and nonletter passthrough logic intact. The original message and output-only operations require no edits; the changed inverse call continues to consume the ciphertext. ROT13 is its own inverse, so positive 13 is equivalent to backward thirteen modulo 26; an unsigned parameter requires this nonnegative representation. The algorithm evidence, not merely its name, establishes case and nonletter behavior.



Source: `Main.java`. Selected original lines: 2,4-6,8,12,14. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    static String cipher(String text, int shift) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `        for (char ch : text.toCharArray()) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `            int base = ch >= 'A' && ch <= 'Z' ? 'A' : ch >= 'a' && ch <= 'z' ? 'a' : -1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `            result.append(base < 0 ? ch : (char)(base + (ch - base + shift + 26) % 26));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        return result.toString();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        String encrypted = cipher("Zoe, meet Max by the Old Bridge at six!", 3);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        System.out.println(cipher(encrypted, -3));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **226 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **293 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 207 tokens (versus 226); removes `static String cipher(String text, int shift) {`.
- Without L4: 204 tokens (versus 226); removes `for (char ch : text.toCharArray()) {`.
- Without L5: 161 tokens (versus 226); removes `int base = ch >= 'A' && ch <= 'Z' ? 'A' : ch >= 'a' && ch <= 'z' ? 'a' : -1;`.
- Without L6: 174 tokens (versus 226); removes `result.append(base < 0 ? ch : (char)(base + (ch - base + shift + 26) % 26));`.
- Without L8: 214 tokens (versus 226); removes `return result.toString();`.
- Without L12: 189 tokens (versus 226); removes `String encrypted = cipher("Zoe, meet Max by the Old Bridge at six!", 3);`.
- Without L14: 207 tokens (versus 226); removes `System.out.println(cipher(encrypted, -3));`.
