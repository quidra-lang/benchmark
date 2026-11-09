# Task B: 78_bank_account / R

The failed line combines the existing one-based operation number, unchanged command text and exact suffix `failed (insufficient funds)`, with explicit spaces and parentheses. For the first failed command it is `op 2: withdraw Leo 4000 failed (insufficient funds)`. There is one line terminator; neither the transaction text nor the suffix is reconstructed from account balances.

result holds the exact suffix and sprintf/cat combines i,command,result with the explicit spaces and newline.

Evidence is from `main.R`, L21,L22.

- L21: `result <- if (success) "ok" else "failed (insufficient funds)"`
- L22: `cat(sprintf("op %d: %s %s\n", number, transactions[number], result))`

Minimization: Only the final result/suffix construction and failed-line expression are necessary. The question excludes balance tracing, so account updates and transaction data need not be selected. The selected complete original lines, in source order, cost 61 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 61, and the complete source costs 500. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
