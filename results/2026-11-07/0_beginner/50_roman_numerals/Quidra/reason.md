# Task B selection: 50_roman_numerals / Quidra

## Answer requirements

Connect Roman-numeral encoding of 1994 with decoding the generated result. Trace the remaining-value changes that create its subtractive symbol pairs, then show how the reverse conversion reads those symbol pairs and combines signed contributions. Identify how the decoder receives the encoded numeral rather than the original integer, and explain the boundary between the two conversion operations without describing unrelated inputs.

## Answer and source evidence

Starting remaining=1994, encode M leaving 994, CM leaving 94, XC leaving 4, and IV leaving 0: MCMXCIV. The decoder receives roman, not the original integer. Contributions are 1000,-100,+1000,-10,+100,-1,+5=1994. Encoding consumes remaining using descending value/symbol pairs; decoding consults each single-symbol value and its neighboring larger symbol, with negative contributions for subtractive pairs. Inputs other than the supplied 1994 and final text rendering add no necessary conversion evidence.

The decoder scans right to left and compares current with the symbol to its right held in next, which implements the same signed sum.

Selected `main.qui` lines: 3, 4, 5, 6, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
