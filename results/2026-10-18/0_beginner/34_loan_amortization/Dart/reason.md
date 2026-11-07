# Task B selection: 34_loan_amortization / Dart

Explain the capped final payment, the resulting principal and balance, and accumulation before loop termination.

When balance plus interest is less than 50000, the minimum makes the payment equal to balance plus interest. Subtracting interest from payment gives exactly the balance, so the balance update reaches zero. The payment is added to total paid in this iteration before the positive-balance test fails.

The import resolves the Dart `math` alias to `dart:math`, whose documented `min` operation selects the smaller operand. The interest formula, starting balance, other totals, and output text do not affect this conditional explanation.

Source: `main.dart`, original lines 1, 5, 8–10, 12. The previous excerpt measures 70 tokens; this evidence set measures 83 tokens.

## Current token measurement

Task A: **224 tokens**. Task B: **83 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
