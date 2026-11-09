# Task B: 14_moving_average / R

Use the positive named window w consistently for the first complete end-day, slice start and divisor. With ten sales, complete end-days are w through 10 and each slice is day-w+1 through day. At w=5 the labels are day 5 through day 10: six results. Put a w>length(sales) guard before iteration that emits `no complete window` once and bypasses averaging; w=11 takes that guard. Divide each complete-window sum by w as a real quotient before the existing display formatting.

The current mean(slice) already uses real division. R 11:10 is descending, so the oversized-window guard must precede colon-range construction to avoid invalid/incomplete slices.

Evidence is from `main.R`, L1,L2,L3,L4,L5.

- L1: `sales <- c(120, 135, 98, 143, 160, 152, 171, 149, 188, 176)`
- L2: `window <- 3`
- L3: `for (day in window:length(sales)) {`
- L4: `average <- mean(sales[(day - window + 1):day])`
- L5: `cat(sprintf("day %d: %.2f\n", day, average))`

Minimization: The sales binding, named window, iteration/slice arithmetic and output are exactly the sites that must agree. No new source implementing the proposed behavior is inserted. The selected complete original lines, in source order, cost 129 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 129, and the complete source costs 131. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
