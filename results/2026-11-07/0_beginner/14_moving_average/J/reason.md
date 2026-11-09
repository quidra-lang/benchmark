# Task B: 14_moving_average / J

Use the positive named window w consistently for the first complete end-day, slice start and divisor. With ten sales, complete end-days are w through 10 and each slice is day-w+1 through day. At w=5 the labels are day 5 through day 10: six results. Put a w>length(sales) guard before iteration that emits `no complete window` once and bypasses averaging; w=11 takes that guard. Divide each complete-window sum by w as a real quotient before the existing display formatting.

The current named window participates in the J index/count arithmetic and % division. The guard must precede construction of i. with a negative count, since that can produce a descending sequence rather than the intended empty report.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6.

- L2: `sales =. 120 135 98 143 160 152 171 149 188 176`
- L3: `window =. 3`
- L4: `for_index. (window-1)+i.(#sales)-window-1 do.`
- L5: `total =. +/ ((index-window-1)+i.window){sales`
- L6: `smoutput 'day ', (":>:index), ': ', , '2' 8!:2 total%window`

Minimization: The sales binding, named window, iteration/slice arithmetic and output are exactly the sites that must agree. No new source implementing the proposed behavior is inserted. The selected complete original lines, in source order, cost 136 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 136, and the complete source costs 156. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
