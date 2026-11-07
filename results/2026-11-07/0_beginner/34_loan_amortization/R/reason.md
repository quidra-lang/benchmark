# Task B: 34_loan_amortization / R

Month 1 advances the label before processing: balance 1000000 earns integer interest 10000; payment is min(50000,1010000)=50000, principal is 40000, and the next balance is 960000. Interest and paid totals update before the record is emitted, so that line shows the completed month. On the final partial month the same minimum caps payment at balance+interest and therefore makes remaining principal exactly zero instead of overpaying.

floor(balance/100) supplies integer-valued interest; min caps payment, then principal/balance/totals update before cat. R values here remain exact small integers in numeric storage.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13.

- L1: `balance <- 1000000`
- L2: `month <- 0`
- L3: `total_interest <- 0`
- L4: `total_paid <- 0`
- L5: `while (balance > 0) {`
- L6: `month <- month + 1`
- L7: `interest <- balance %/% 100`
- L8: `payment <- min(50000, balance + interest)`
- L9: `principal <- payment - interest`
- L10: `balance <- balance - principal`
- L11: `total_interest <- total_interest + interest`
- L12: `total_paid <- total_paid + payment`
- L13: `cat(sprintf("month %d: interest=%d principal=%d balance=%d\n", month, interest, principal, balance))`

Minimization: The incoming state, ordered monthly update and record emission are all relevant. The schedule termination summary is unnecessary because the question asks one operation and its final-payment cap. The selected complete original lines, in source order, cost 186 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 186, and the complete source costs 224. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
