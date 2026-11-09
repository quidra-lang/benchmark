# Task B selection: 58_morse_code / Quidra

## Answer requirements

Suppose a decoder must accept its Morse text as the only message input and must match complete code tokens exactly, never a prefix. Explain where and how its word splitting, letter-token splitting, reverse lookup and result joining must agree so . maps to E and .- maps to A independently and word spaces are restored. Cite the existing stages and identify which already meet the requirement; do not change the Morse table or use original-message letters as a fallback.

## Answer and source evidence

The existing decoder already consumes only encoded Morse text. Split words at ` / `, split each word into space-separated complete code tokens, perform an exact reverse-key lookup, concatenate letters, then join words with one space. The table maps complete token . to E and .- to A separately; no prefix search or original-message fallback participates. A separately callable decoder should receive encoded as its argument and retain these same stages.

index_of on the codes array uses equatable exact string equality, not starts_with; its returned index selects the corresponding alphabet character.

Selected `main.qui` lines: 3, 4, 6, 8, 19, 20, 21, 22, 23. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
