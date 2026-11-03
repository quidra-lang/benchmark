# Task B selection: 09_reverse_words / Java

## Common answer requirements

1. Derive how the final word line becomes the beginning of each reversed result.
2. Distinguish character reversal from word-order reversal and explain spaces in both lines.

## Answer supported by the excerpt

Character reversal yields `enil elgnis a htiw strats margorp yreve`: the last word contributes enil, and the original space characters are reversed along with letters. Word-order reversal yields `line single a with starts program every`: line remains spelled line, words move as units, and one space separates adjacent words. There is no added leading or trailing space.

## Source evidence and dependencies

Selected `Main.java` lines: 5-7. The excerpt preserves these complete lines in their original order and indentation.

The sentence literal is required for the exact characters and final word. The first operation reverses characters or bytes; the second tokenizes words and reverses their order, or scans/inserts them backward. Joining/separator state establishes the distinct treatment of spaces. Explicit stream writes also retain the newline sites separating the two results.

## Language semantics and minimization

Use the language's ordinary evaluation, indexing, iteration and numeric semantics, and the documented behavior of the standard-library operations visible in the excerpt. The Task B assumptions apply; this is not a build or correctness verification. Neither reversal operation alone answers the comparison. Omitting the literal loses the exact resulting prefixes. The selected data and both transformations are smaller than complete wrapper/import/flush code and avoid reproducing standard split/reverse/join implementations.

The selected excerpt contains **85 tokens** under `metric/tokenizer.py`. The contiguous source span from its first through last selected line contains 85 tokens; the complete source contains 125 tokens. These counts compare source-line sets, not LLM billing. Boilerplate and unchanged processing are omitted when they contribute no required fact. The excerpt need not be a standalone compilable program; omitted closing delimiters are not evidence for additional behavior.
