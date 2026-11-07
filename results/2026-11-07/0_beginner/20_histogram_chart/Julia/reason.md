# Task B: 20_histogram_chart / Julia

Keep the retrieved day and original numeric count. Compute only the bar length as ceil(count/2), or positive-integer (count+1) quotient 2. Mon 7 produces four asterisks and still prints 7; Tue 12 produces six and still prints 12. Leave the ordered day/count pairing intact and replace only the repetition operand in the existing line construction.

zip binds each day/count pair in order; repeat("*",...) takes the scaled ceiling while the interpolation retains amount.

Evidence is from `main.jl`, L1,L2,L3.

- L1: `for (day, amount) in`
- L2: `zip(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], [7, 12, 4, 15, 9, 18, 11])`
- L3: `println(day, " | ", repeat("*", amount), " ", amount)`

Minimization: The day/count bindings and the bar/output expression are needed to show that only display length changes. No other reporting state exists. The selected complete original lines, in source order, cost 110 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 110, and the complete source costs 112. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
