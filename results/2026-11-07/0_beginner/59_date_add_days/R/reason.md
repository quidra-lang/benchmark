# Task B: 59_date_add_days / R

Keep an immutable/original formatted date for the left side and replace the displayed plus with minus. For each subtracted day decrement day; when it becomes zero, decrement month, wrap month 0 to December and decrement year, then recompute that previous month's length using its year's Gregorian leap status and set day to that length. Pass the final components to the existing zero-padded formatter. In the 120-day case, stepping backward from 2023-11-01 crosses to 2023-10-31; the final date is 2023-07-18.

month_days already computes Gregorian February length. Use it after previous-month/year selection; preserve the original date string while modifying numeric components.

Evidence is from `main.R`, L1,L2,L3,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24.

- L1: `days_in_month <- function(year, month) {`
- L2: `leap <- year %% 400 == 0 || (year %% 4 == 0 && year %% 100 != 0)`
- L3: `if (month == 2 && leap) 29 else c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month]`
- L6: `dates <- c("1999-12-25", "2000-02-27", "2021-02-20", "2023-11-15", "2026-10-17")`
- L7: `additions <- c(10, 3, 14, 120, 1500)`
- L8: `for (i in seq_along(dates)) {`
- L9: `parts <- as.integer(strsplit(dates[i], "-", fixed = TRUE)[[1]])`
- L10: `year <- parts[1]`
- L11: `month <- parts[2]`
- L12: `day <- parts[3]`
- L13: `for (step in seq_len(additions[i])) {`
- L14: `day <- day + 1`
- L15: `if (day > days_in_month(year, month)) {`
- L16: `day <- 1`
- L17: `month <- month + 1`
- L18: `if (month > 12) {`
- L19: `month <- 1`
- L20: `year <- year + 1`
- L21: `}`
- L22: `}`
- L23: `}`
- L24: `cat(sprintf("%s + %d days = %04d-%02d-%02d\n", dates[i], additions[i], year, month, day))`

Minimization: The current date helper/month-length rule, original binding, day loop and output connect every proposed boundary change. Unrelated day-count cases need not be traced, although some share the same source line. The selected complete original lines, in source order, cost 493 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 496, and the complete source costs 498. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
