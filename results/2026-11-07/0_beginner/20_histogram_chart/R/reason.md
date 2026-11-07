# Task B: 20_histogram_chart / R

Keep the retrieved day and original numeric count. Compute only the bar length as ceil(count/2), or positive-integer (count+1) quotient 2. Mon 7 produces four asterisks and still prints 7; Tue 12 produces six and still prints 12. Leave the ordered day/count pairing intact and replace only the repetition operand in the existing line construction.

The vectorized strrep operand becomes ceiling(amounts/2); the numeric amounts operand in sprintf remains unscaled.

Evidence is from `main.R`, L1,L2,L3.

- L1: `days <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")`
- L2: `amounts <- c(7, 12, 4, 15, 9, 18, 11)`
- L3: `cat(sprintf("%s | %s %d\n", days, strrep("*", amounts), amounts), sep = "")`

Minimization: The day/count bindings and the bar/output expression are needed to show that only display length changes. No other reporting state exists. The selected complete original lines, in source order, cost 118 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 118, and the complete source costs 118. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
