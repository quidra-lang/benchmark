# Task B selection: 09_reverse_words / Quidra

## Common answer requirements

1. Derive how the final word line becomes the beginning of each reversed result.
2. Distinguish character reversal from word-order reversal and explain spaces in both lines.

## Answer supported by the excerpt

Character reversal yields `enil elgnis a htiw strats margorp yreve`: the last word contributes enil, and the original space characters are reversed along with letters. Word-order reversal yields `line single a with starts program every`: line remains spelled line, words move as units, and one space separates adjacent words. There is no added leading or trailing space.

## Source evidence and dependencies

The excerpt contains lines 1–3 of `main.qui` verbatim and in source order.

Line 1 supplies the sentence and its final word. Line 2 reverses the string with `[::-1]`, moving its characters and spaces together. Line 3 uses `.split(" ")` to separate words, `[::-1]` to reverse their order, and `.join(" ")` to put one ASCII space between adjacent words. Each `println` ends its result with a newline.

## Language semantics and minimization

All three lines are needed. Omitting the literal loses the concrete input and its final word. Omitting either `println` loses the operations that establish that result's prefix and treatment of spaces. The documented slice, split, join, and `println` semantics supply the remaining behavior.

The complete Task A source and the Task B excerpt each contain **53 tokens** under `metric/tokenizer.py`.

## Quidra develop re-evaluation (2026-11-01)

Target: Quidra 0.6.0, develop 5c53a97d8d4b.
Question category: Code comprehension.
Evidence was reselected from the revised Task A program, using the
question and the specific answer requirements documented above.
Complete main.qui source lines: 1, 2.
Every retained line is an exact verbatim source line in source order.
Equal-text alternative occurrences have equal token cost; the earliest
valid in-order occurrence was used. Unrelated lines were excluded.
Tokenizer: Task A 58 tokens; Task B 58 tokens.
This uses the prior semantic rationale as a constraint; its automated
line checks do not prove globally minimal evidence or compilation.

## Quidra develop re-evaluation (2026-11-02)

Target: Quidra 0.6.0, develop 33b7b6a23a79.
Question category: Code comprehension.
Evidence was reselected from the revised Task A program, using the
question and the specific answer requirements documented above.
Complete main.qui source lines: 1, 2.
Every retained line is an exact verbatim source line in source order.
Equal-text alternative occurrences have equal token cost; the earliest
valid in-order occurrence was used. Unrelated lines were excluded.
Tokenizer: Task A 58 tokens; Task B 58 tokens.
This uses the prior semantic rationale as a constraint; its automated
line checks do not prove globally minimal evidence or compilation.
