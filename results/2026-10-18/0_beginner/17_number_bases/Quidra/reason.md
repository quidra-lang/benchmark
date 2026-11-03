# Task B selection: 17_number_bases / Quidra

## Question and answer requirements

[Modification analysis]

Using the Task A source as evidence, explain which parts would need to change and how to satisfy the proposed requirements below. Do not edit the program or produce modified source code.

Proposed requirements:
Modify the program so that hexadecimal digits with values 10 through 15 are printed as lowercase a through f instead of uppercase A through F. Apply this change only to the hexadecimal representation after hex=; keep the original decimal value, binary representation, octal representation, labels and line order unchanged.

Preserve the rules for zero, prefixes and leading zeros. All other Task A requirements remain unchanged.

## Evidence and answer

The only hexadecimal formatting site is the hex={value:base=16,upper} interpolation in the output statement. Remove only the upper option from that field to select lowercase a-f while preserving decimal value, binary and octal fields, base=16, labels, line order, zero and leading-zero rules. These format semantics are guaranteed by Core; the library/formatter implementation is not needed.

## Minimality and language guarantees

Selected main.qui lines: 3. The selection copies complete source lines verbatim in source order. It retains the data, calls, control flow and ordering keys needed by this question; the unselected source (such as output detail or unrelated computation) does not add a required fact. Core and first-party package functions, native collections, and stable keyed sorting are treated as specified contracts, not as user-defined functions needing implementation inspection. The source-only excerpt contains 45 tokens, against 96 for the full program, using metric/tokenizer.py. Individual lines and possible alternative evidence sets were compared to retain only dependencies for this question; this is not a formal proof of global minimality or a claim of compilation/testing.

Core develop: 33b7b6a23a79; Quidra 0.6.0.
