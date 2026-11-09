# Task B selection: 45_anagram_groups / Quidra

## Answer requirements

For apple's anagram signature, locate the lookup, condition or default-creation operation that chooses a new group rather than an existing one. Explain the decision from the source's actual key representation and absent-key behavior. Focus on this one group-selection decision; do not trace all words or output ordering.

## Answer and source evidence

Sorting apple produces the signature aelpp. Python setdefault chooses an existing list or inserts a new empty list for this absent key, then append adds the word; the new key creates a new group. Quidra group_by performs the corresponding signature-key grouping: a previously unseen signature starts a new group, while an equal key selects its existing group. The question supplies apple, so the word collection and unrelated output ordering are unnecessary.

The parallel signatures and words arrays associate each sorted-character key with its original word; documented group_by semantics supply missing-group creation.

Selected `main.qui` lines: 5, 6. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
