# Task B selection: 85_text_justify / Quidra

## Answer requirements

Explain the operation that builds one nonfinal justified line with at least two words, from paragraph word tokens through greedy packing to the completed 30-character string. Use the token "names," to show how punctuation remains inside a token and contributes to packing length, then identify total spaces, gap count, quotient/remainder distribution and framing by vertical bars. Explain how the source chooses a different padding path for final or single-word lines, without formatting every paragraph line.

## Answer and source evidence

Whitespace tokenization preserves punctuation within tokens, so names, remains one six-character word. Greedy packing fits whole words with at least one interword space within width30. For a nonfinal line of at least two words, total padding is30 minus word-character count; divide it by number_of_words-1, giving base spaces per gap and one extra space to each leftmost remainder gap. Final/single-word lines use single internal spaces and right padding instead. The completed thirty-character line is framed by literal vertical bars, which are outside its width.

text.layout.justify documents this packing and distribution, and the named width feeds that operation. The library implementation is not additional source evidence under the standard-library semantics rule.

Selected `main.qui` lines: 3, 4, 5, 6, 7. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
