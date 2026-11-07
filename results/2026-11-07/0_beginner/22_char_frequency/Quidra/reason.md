# Task B selection: 22_char_frequency / Quidra

## Answer requirements

Suppose uppercase and lowercase letters must be counted separately, with occurring uppercase letters printed first in A-to-Z order and lowercase letters next in a-to-z order. Explain the changes from scanning the original sentence through letter filtering, count-key selection, ordering and formatted output. Use P and p from the given sentence to derive the two counts that replace their combined count, and show how spaces and punctuation remain excluded.

## Answer and source evidence

Keep the original case while scanning and use distinct uppercase/lowercase keys, accepting only ASCII letters. Print keys in ASCII order, which puts A..Z before a..z. The original sentence contains two uppercase P characters and seven lowercase p characters, replacing the combined count of nine. Spaces and the exclamation mark are rejected by the letter filter; the `letter: count` line format remains.

Change ignore_case to false in ascii_words; characters/frequencies then retain case and sorted_entries orders the resulting ASCII keys.

Selected `main.qui` lines: 4, 5, 6, 7, 8. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
