# Task B selection: 72_undo_redo_editor / Quidra

## Answer requirements

Follow the local command-parsing block for type hello world and delete 5. Identify how each command name is recognized, where its payload begins and how the complete remainder hello world keeps its internal space, while 5 becomes a numeric deletion count. Explain how those parsed values reach the buffer update; do not trace the undo/redo history.

## Answer and source evidence

The type-prefix test recognizes `type ` and takes the complete remainder starting at character index5, preserving the internal space in hello world as the buffer suffix. The delete path takes the remainder after `delete ` from index7 and converts "5" with int; the buffer slice removes the requested final characters (clamped at zero in Quidra). No whitespace tokenization splits the type payload. History updates and other commands are outside this local parse-to-update block.



Selected `main.qui` lines: 27, 28, 29, 30, 31, 32. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
