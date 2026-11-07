# Task B: 74_calendar_month / R

For year 2026,month 8, the integer weekday formula gives 6 with Sunday=0, and August has 31 days. The header is `August 2026`, followed by `Su Mo Tu We Th Fr Sa`. Six blank width-two fields precede the first day, so the first week line is nineteen spaces followed by `1`. Each seven-field week is joined by single spaces; the last line is `30 31`, with no appended blank columns. A separator newline is emitted before every calendar after the first, giving one blank line between months.

The integer-valued weekday calculation and rep("  ",weekday) initialize leading fields; the final-day condition flushes the partial row as stored.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25.

- L1: `month_names <- c(`
- L2: `"January", "February", "March", "April", "May", "June", "July", "August", "September", "October",`
- L3: `"November", "December"`
- L4: `)`
- L5: `months <- list(c(2024, 2), c(2026, 8), c(2026, 11))`
- L6: `for (index in seq_along(months)) {`
- L7: `year <- months[[index]][1]`
- L8: `month <- months[[index]][2]`
- L9: `if (index > 1) cat("\n")`
- L10: `cat(sprintf("%s %d\nSu Mo Tu We Th Fr Sa\n", month_names[month], year))`
- L11: `adjusted_year <- if (month < 3) year - 1 else year`
- L12: `adjusted_month <- if (month < 3) month + 12 else month`
- L13: `century <- adjusted_year %/% 100`
- L14: `within <- adjusted_year %% 100`
- L15: `weekday <- (1 + (13 * (adjusted_month + 1)) %/% 5 + within + within %/% 4 + century %/% 4 + 5 * century + 6) %% 7`
- L16: `leap <- year %% 4 == 0 && (year %% 100 != 0 || year %% 400 == 0)`
- L17: `days <- if (month == 2 && leap) 29 else c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month]`
- L18: `fields <- rep("  ", weekday)`
- L19: `for (day in seq_len(days)) {`
- L20: `fields <- c(fields, sprintf("%2d", day))`
- L21: `if (length(fields) == 7 || day == days) {`
- L22: `cat(paste(fields, collapse = " "), "\n", sep = "")`
- L23: `fields <- character(0)`
- L24: `}`
- L25: `}`

Minimization: The month data/name table, integer weekday computation, length rule, blank-field construction, wrapping and output are needed for this complete calendar. Imports/main wrappers are not relevant. The selected complete original lines, in source order, cost 625 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 625, and the complete source costs 627. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
