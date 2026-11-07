# Task B: 34_loan_amortization / Julia

Month 1 advances the label before processing: balance 1000000 earns integer interest 10000; payment is min(50000,1010000)=50000, principal is 40000, and the next balance is 960000. Interest and paid totals update before the record is emitted, so that line shows the completed month. On the final partial month the same minimum caps payment at balance+interest and therefore makes remaining principal exactly zero instead of overpaying.

div(balance,100) supplies integer interest; min caps payment, and balance -= principal precedes totals and @printf.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11.

- L2: `balance, month, total_interest, total_paid = 1000000, 0, 0, 0`
- L3: `while balance > 0`
- L4: `month += 1`
- L5: `interest = div(balance, 100)`
- L6: `payment = min(50000, balance + interest)`
- L7: `principal = payment - interest`
- L8: `balance -= principal`
- L9: `total_interest += interest`
- L10: `total_paid += payment`
- L11: `println("month $month: interest=$interest principal=$principal balance=$balance")`

Minimization: The incoming state, ordered monthly update and record emission are all relevant. The schedule termination summary is unnecessary because the question asks one operation and its final-payment cap. The selected complete original lines, in source order, cost 158 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 158, and the complete source costs 206. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
