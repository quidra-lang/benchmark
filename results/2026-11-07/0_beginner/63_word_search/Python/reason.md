# Task B selection: 63_word_search / Python

## Answer requirements

At a candidate search for TIGER from row 0, column 0 in direction E, identify the local bindings used for the word, start cell and direction offsets. Explain how the corresponding cell-comparison block resolves those names and obtains the board, whether through parameters, enclosing scope or inline iteration. Focus on this one candidate block, without tracing the whole search.

## Answer and source evidence

For the candidate TIGER at row/column 0,0 and E, the direction offsets are dr=0,dc=1. The comparison reads each board cell at start plus offset times character index against the corresponding word character. Python word is a find parameter, row/column and direction tuple fields are locals, and board/directions are enclosing module bindings. Quidra word/board are value parameters to search, r/c/direction/k are local loop bindings and offset arrays are local. The selected call connects the outer word to that parameter; full board contents and other search decisions are not required for name resolution.



Selected `main.py` lines: 1, 13, 14, 25, 26, 27, 28, 35, 36, 37, 43, 44. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
