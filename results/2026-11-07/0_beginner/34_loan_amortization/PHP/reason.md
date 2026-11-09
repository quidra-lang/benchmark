## Answer and source evidence

The initial balance is 1000000 and month 0. Each positive-balance iteration advances month first, computes interest=floor/intdiv(balance/100), caps payment at min(50000,balance+interest), derives principal=payment-interest and subtracts it from balance. Month 1 therefore has interest 10000, payment 50000, principal 40000 and ending balance 960000. Both totals update before printing the month record. When balance+interest is below 50000, the cap makes principal exactly the remaining balance, ending at zero. Initial state and every monthly dependency/ordering are needed; end-of-schedule total display is unrelated to this one-step operation.

## Selection and minimization

The excerpt contains the complete original source lines listed in their original order. PHP array/string/arithmetic and formatting operations are interpreted with their standard runtime semantics; no stronger static invariant is inferred. Blank lines, closing delimiters whose structural role is already determined, and unrelated calculations/output are omitted. Each retained data declaration, binding, operation, condition, or output argument supplies one of the facts above; replacing the selected operations with their callers would conceal those facts, while selecting the entire routine would add unrelated evidence. No Task B modification is implemented.
