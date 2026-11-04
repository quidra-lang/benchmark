# Task B selection: 58_morse_code / C

## Common answer requirements

Trace decoding from generated Morse around the standalone ME followed by AT, including token-to-letter lookup and recovery of spaces.

## Source evidence

The forward table supplies M=--, E=., A=.-, and T=-. Encoding generates “-- . / .- -” at the requested boundary. The whitespace token loop treats the slash token as a literal space and maps other tokens to letters. The reverse lookup takes its keys from generated tokens and its letters from the code table, so reconstruction never rereads original message characters.

## Minimization

Only the code entries through T are needed for this trace when they occupy independent lines; earlier entries establish positional lookup. Packed lines are kept verbatim. Printing is needed only if it performs a required join or directly emits a decoded character.

Selected complete lines of `main.c`: 5–7, 9–20, 22–31. The prior excerpt measured 651 tokens; this excerpt measures 583 with `metric/tokenizer.py`.
