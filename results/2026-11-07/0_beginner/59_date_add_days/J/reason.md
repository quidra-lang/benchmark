# Task B: 59_date_add_days / J

Keep an immutable/original formatted date for the left side and replace the displayed plus with minus. For each subtracted day decrement day; when it becomes zero, decrement month, wrap month 0 to December and decrement year, then recompute that previous month's length using its year's Gregorian leap status and set day to that length. Pass the final components to the existing zero-padded formatter. In the 120-day case, stepping backward from 2023-11-01 crosses to 2023-10-31; the final date is 2023-07-18.

The current forward loop computes monthlength, advances day and wraps month/year. Reverse those transitions and move length/leap computation to the resulting previous month when a boundary is crossed.

Evidence is from `main.ijs`, L1,L2,L3,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24.

- L1: `date =: 3 : 0`
- L2: `'year month day' =. y`
- L3: `(_4{.'0000',":year),'-',(_2{.'0',":month),'-',_2{.'0',":day`
- L6: `common =. 31 28 31 30 31 30 31 31 30 31 30 31`
- L7: `for_row. 5 4$1999 12 25 10 2000 2 27 3 2021 2 20 14 2023 11 15 120 2026 10 17 1500 do.`
- L8: `'year month day days' =. row`
- L9: `original =. date year,month,day`
- L10: `for_added. i.days do.`
- L11: `leap =. (0=400|year)+.(0=4|year)*.0~:100|year`
- L12: `monthlength =. (month-1){common`
- L13: `if. (month=2)*.leap do. monthlength =. 29 end.`
- L14: `day =. >:day`
- L15: `if. day>monthlength do.`
- L16: `day =. 1`
- L17: `month =. >:month`
- L18: `if. month>12 do.`
- L19: `month =. 1`
- L20: `year =. >:year`
- L21: `end.`
- L22: `end.`
- L23: `end.`
- L24: `smoutput original,' + ',(":days),' days = ',date year,month,day`

Minimization: The current date helper/month-length rule, original binding, day loop and output connect every proposed boundary change. Unrelated day-count cases need not be traced, although some share the same source line. The selected complete original lines, in source order, cost 414 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 426, and the complete source costs 436. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
