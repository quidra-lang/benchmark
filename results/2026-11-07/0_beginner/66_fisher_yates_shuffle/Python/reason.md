# Task B selection: 66_fisher_yates_shuffle / Python

## Answer requirements

Follow the final shuffle iteration i=1 through one random-state update, selection of j and swap/no-change handling, then loop termination. Identify why j can only be 0 or 1, why a self-swap still consumes its random value and why no i=0 iteration follows. Cite the actual boundaries and local update order rather than tracing the complete deck.

## Answer and source evidence

At i=1, update MINSTD once, then j=state%(i+1)=state%2, giving only 0 or 1. The unconditional swap either exchanges two entries or swaps the same entry with itself, after the random value has already been consumed. The descending loop excludes 0 (Python exclusive stop 0; Quidra inclusive lower bound 1), so no further shuffle iteration follows. Seed, deck construction and printing are unnecessary for this local boundary question.



Selected `main.py` lines: 4, 5, 6, 7. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
