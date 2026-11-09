# Task B selection: 34_loan_amortization / Python

## Answer requirements

Explain one monthly repayment operation from its incoming balance and payment limit to the month's interest, actual payment, principal portion, printed record and next balance. Use month 1 as a concrete calculation, then explain how the same operation caps a final partial payment. Identify the ordering of month-number advancement, total updates and record emission so the label and balance belong to the month just processed; do not trace the entire repayment schedule.

## Answer and source evidence

Month 1 starts at 1000000 with month advanced from 0 to 1. Interest is 10000, actual payment 50000, principal 40000 and next balance 960000. Interest and actual payment enter their respective totals before the record emits the processed month and updated balance. The payment minimum caps a final payment at remaining balance plus interest, so principal clears that balance without overpayment. Final summary formatting is outside the one-month operation.



Selected `main.py` lines: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
