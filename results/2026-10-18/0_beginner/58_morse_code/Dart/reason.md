# Task B selection: 58_morse_code / Dart

## Common answer requirements

Trace decoding from generated Morse around the standalone ME followed by AT, including token-to-letter lookup and recovery of spaces.

## Source evidence

The forward table supplies M=--, E=., A=.-, and T=-. Encoding generates “-- . / .- -” at the requested boundary. The decoder splits the generated string at the slash word separator, tokenizes each word at the letter boundaries, and restores an ordinary space when joining decoded words. The reverse lookup takes its keys from generated tokens and its letters from the code table, so reconstruction never rereads original message characters.

## Minimization

Only the code entries through T are needed for this trace when they occupy independent lines; earlier entries establish positional lookup. Packed lines are kept verbatim. Printing is needed only if it performs a required join or directly emits a decoded character.

Selected complete lines of `main.dart`: 2–22, 39–49. The prior excerpt measured 458 tokens; this excerpt measures 341 with `metric/tokenizer.py`.

## Current token measurement

Task A: **480 tokens**. Task B: **340 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
