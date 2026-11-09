# Task B: 34_loan_amortization / J

Month 1 advances the label before processing: balance 1000000 earns integer interest 10000; payment is min(50000,1010000)=50000, principal is 40000, and the next balance is 960000. Interest and paid totals update before the record is emitted, so that line shows the completed month. On the final partial month the same minimum caps payment at balance+interest and therefore makes remaining principal exactly zero instead of overpaying.

The while loop increments month, floors one-percent interest, caps payment, computes principal and subtracts it from balance in that order.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14.

- L2: `balance =. 1000000`
- L3: `month =. 0`
- L4: `totalinterest =. 0`
- L5: `totalpaid =. 0`
- L6: `while. balance>0 do.`
- L7: `month =. >:month`
- L8: `interest =. <.balance%100`
- L9: `payment =. 50000 <. balance+interest`
- L10: `principal =. payment-interest`
- L11: `balance =. balance-principal`
- L12: `totalinterest =. totalinterest+interest`
- L13: `totalpaid =. totalpaid+payment`
- L14: `smoutput 'month ',(":month),': interest=',(":interest),' principal=',(":principal),' balance=',":balance`

Minimization: The incoming state, ordered monthly update and record emission are all relevant. The schedule termination summary is unnecessary because the question asks one operation and its final-payment cap. The selected complete original lines, in source order, cost 165 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 165, and the complete source costs 215. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
