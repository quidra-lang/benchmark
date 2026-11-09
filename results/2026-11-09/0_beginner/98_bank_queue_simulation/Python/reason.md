# Task B selection: 98_bank_queue_simulation / Python

## Answer requirements

Suppose the MINSTD state binding is renamed rng_state. Identify its introduction and the references in the recurrence and random-value reads that must follow that rename. Explain why the independently bound accumulated arrival time is not the same state and must keep its own references. Focus on resolving this one state name, without tracing customer assignments.

## Answer and source evidence

Rename the state introduction and both recurrence left/right references to rng_state, plus the state reads used for arrival-gap modulo5 and service-time modulo7. arrival is separately initialized and accumulated; it is an elapsed-arrival-time binding, not the MINSTD recurrence state, so its own name/references remain. Teller scheduling and reporting are unrelated to this name-resolution change.



Selected `main.py` lines: 1, 2, 6, 7, 8, 9. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
