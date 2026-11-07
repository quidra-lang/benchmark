# Task B: 74_calendar_month / J

For year 2026,month 8, the integer weekday formula gives 6 with Sunday=0, and August has 31 days. The header is `August 2026`, followed by `Su Mo Tu We Th Fr Sa`. Six blank width-two fields precede the first day, so the first week line is nineteen spaces followed by `1`. Each seven-field week is joined by single spaces; the last line is `30 31`, with no appended blank columns. A separator newline is emitted before every calendar after the first, giving one blank line between months.

The month-name table and integer formula bind header/weekday; the line starts with weekday*3 blank characters and a column counter flushes on Saturday or the final day, then resets instead of padding the final row.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34.

- L2: `names =. ;:'January February March April May June July August September October November December'`
- L3: `lengths =. 31 28 31 30 31 30 31 31 30 31 30 31`
- L4: `months =. 3 2$2024 2 2026 8 2026 11`
- L5: `for_index. i.3 do.`
- L6: `'year month' =. index{months`
- L7: `y =. year`
- L8: `m =. month`
- L9: `if. m<3 do.`
- L10: `m =. m+12`
- L11: `y =. y-1`
- L12: `end.`
- L13: `century =. <.y%100`
- L14: `within =. 100|y`
- L15: `h =. 7|1+(<.(13*(m+1))%5)+within+(<.within%4)+(<.century%4)+5*century`
- L16: `weekday =. 7|h+6`
- L17: `days =. (month-1){lengths`
- L18: `leap =. (0=400|year)+.(0=4|year)*.0~:100|year`
- L19: `if. (month=2)*.leap do. days =. 29 end.`
- L20: `if. index>0 do. smoutput '' end.`
- L21: `smoutput (>(month-1){names),' ',":year`
- L22: `smoutput 'Su Mo Tu We Th Fr Sa'`
- L23: `line =. (weekday*3)$' '`
- L24: `column =. weekday`
- L25: `for_day. >:i.days do.`
- L26: `if. (day>1)*.column>0 do. line =. line,' ' end.`
- L27: `line =. line,, '2.0' 8!:2 day`
- L28: `column =. >:column`
- L29: `if. (column=7)+.day=days do.`
- L30: `smoutput line`
- L31: `line =. ''`
- L32: `column =. 0`
- L33: `end.`
- L34: `end.`

Minimization: The month data/name table, integer weekday computation, length rule, blank-field construction, wrapping and output are needed for this complete calendar. Imports/main wrappers are not relevant. The selected complete original lines, in source order, cost 508 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 508, and the complete source costs 528. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
