# Task B selection: 34_loan_amortization / Quidra

Explain the final partial repayment, how payment minus interest reduces principal to zero, and inclusion in total_paid before termination.

The loop condition establishes termination at zero. Math min caps payment at50000; when balance+interest is smaller, subtracting interest leaves exactly the remaining principal. The balance update therefore produces zero, and total_paid includes that payment before the next condition stops the loop. The interest rate and initial principal are unnecessary for this conditional relationship. Imported Math semantics suffice without its implementation.

Selected complete source lines: 1, 7, 10, 11, 12, 14. All are verbatim and in source order. A full-source alternative adds unrelated month labels, initial values and printed summaries.

Tokenizer: Task A193; Task B62. Runtime verification is separate.
