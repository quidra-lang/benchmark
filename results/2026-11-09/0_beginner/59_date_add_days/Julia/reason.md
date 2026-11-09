# Task B: 59_date_add_days / Julia

Keep an immutable/original formatted date for the left side and replace the displayed plus with minus. For each subtracted day decrement day; when it becomes zero, decrement month, wrap month 0 to December and decrement year, then recompute that previous month's length using its year's Gregorian leap status and set day to that length. Pass the final components to the existing zero-padded formatter. In the 120-day case, stepping backward from 2023-11-01 crosses to 2023-10-31; the final date is 2023-07-18.

The days_in_month helper already encodes the Gregorian rule. Use it after previous-month/year selection on a backward boundary, then retain the %04d-%02d-%02d result fields.

Evidence is from `main.jl`, L3,L4,L5,L8,L12,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27.

- L3: `function days_in_month(year, month)`
- L4: `leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)`
- L5: `return month == 2 && leap ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month]`
- L8: `for (original, added) in [`
- L12: `("2023-11-15", 120),`
- L14: `]`
- L15: `year, month, day = parse.(Int, split(original, "-"))`
- L16: `for step = 1:added`
- L17: `day += 1`
- L18: `if day > days_in_month(year, month)`
- L19: `day = 1`
- L20: `month += 1`
- L21: `if month > 12`
- L22: `month = 1`
- L23: `year += 1`
- L24: `end`
- L25: `end`
- L26: `end`
- L27: `@printf("%s + %d days = %04d-%02d-%02d\n", original, added, year, month, day)`

Minimization: The current date helper/month-length rule, original binding, day loop and output connect every proposed boundary change. Unrelated day-count cases need not be traced, although some share the same source line. The selected complete original lines, in source order, cost 342 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 430, and the complete source costs 437. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
