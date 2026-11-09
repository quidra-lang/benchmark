# Task B: 20_histogram_chart / J

Keep the retrieved day and original numeric count. Compute only the bar length as ceil(count/2), or positive-integer (count+1) quotient 2. Mon 7 produces four asterisks and still prints 7; Tue 12 produces six and still prints 12. Leave the ordered day/count pairing intact and replace only the repetition operand in the existing line construction.

days and counts are parallel arrays, and n is the retrieved count. Replace n#'*' with a repetition based on ceil n%2; retain n in the numeric text.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6.

- L2: `days =. ;:'Mon Tue Wed Thu Fri Sat Sun'`
- L3: `counts =. 7 12 4 15 9 18 11`
- L4: `for_i. i.7 do.`
- L5: `n =. i{counts`
- L6: `smoutput (>i{days), ' | ', (n$'*'), ' ', ":n`

Minimization: The day/count bindings and the bar/output expression are needed to show that only display length changes. No other reporting state exists. The selected complete original lines, in source order, cost 101 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 101, and the complete source costs 121. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
