# Task B selection: 26_caesar_cipher / Python

## Answer requirements

Explain the string-shift operation from its input message and shift value to its resulting ciphertext. Cover uppercase and lowercase ranges, wraparound, nonletter handling and construction of the result, using Z and the following comma as concrete cases. Identify whether result construction mutates storage or creates/rebinds values in this source, and show which result is supplied to decryption. Do not trace every message character.

## Answer and source evidence

The shift operation constructs a translation from lowercase and uppercase alphabets to their rotated counterparts. Shift 3 maps Z to C with wraparound; a comma has no mapping and is retained. Translation returns a new string rather than mutating the input. The named encrypted result from the +3 call is passed to the -3 call for decryption; no complete message trace is required.

Negative slicing rotates each 26-character alphabet in the opposite direction; str.translate leaves unmapped punctuation intact.

Selected `main.py` lines: 1, 4, 5, 6, 7, 8, 9, 13, 15. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
