# Task B selection: 34_loan_amortization / Java

Month 1 increments 0 to 1, computes interest 10000, caps payment at 50000, pays principal 40000 and leaves 960000. It updates both totals before printing that month and next balance. The same min(payment limit,balance+interest) caps a final partial payment so principal clears the remaining balance rather than overpaying.

Initialization and one complete while-body establish the requested monthly operation. Final lifetime summary prints are not part of the operation.

Selected complete source lines in `Main.java`: 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
