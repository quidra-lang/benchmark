# Task B selection: 17_number_bases / Quidra

## Question and answer requirements

[Modification analysis]

Using the Task A source as evidence, explain which parts would need to change and how to satisfy the proposed requirements below. Do not edit the program or produce modified source code.

Proposed requirements:
Modify the program so that hexadecimal digits with values 10 through 15 are printed as lowercase a through f instead of uppercase A through F. Apply this change only to the hexadecimal representation after hex=; keep the original decimal value, binary representation, octal representation, labels and line order unchanged.

Preserve the rules for zero, prefixes and leading zeros. All other Task A requirements remain unchanged.

## Evidence and answer

The only hexadecimal rendering site is `hex={n.B16}` in the output statement. Change only that member from `B16` to `b16` to select lowercase a-f. Both members return a base-16 string with the same negative-sign, zero, prefix and leading-zero rules; only letter case differs. The selected output line also shows that the decimal value, binary and octal representations, labels and output structure need no change. The loop and its order need no change. These semantics are guaranteed by Core, so no conversion implementation is needed.

## Minimality and language guarantees

Select only main.qui line 2, copied verbatim with its original indentation. The statement establishes the hexadecimal member and every other output field needed to delimit the requested change. The array and loop header do not affect how to change hexadecimal letter case and are unnecessary evidence. No other source line identifies the conversion, so omitting this line would lose the required evidence; adding the header would only increase the token count.

The excerpt contains 34 tokens, against 74 for the full program, using metric/tokenizer.py unchanged. This is a source review and token measurement, not a claim of compilation or execution.

Core develop: 013dd3012769; Quidra 0.6.0.

Measurement: Task A 74; Task B 34. Tokenizer: metric/tokenizer.py, unchanged.
