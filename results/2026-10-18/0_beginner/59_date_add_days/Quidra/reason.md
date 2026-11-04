# Task B selection: 59_date_add_days / Quidra

## Answer requirements

Locate day stepping and month/year rollover, preserve Gregorian month lengths, and reverse direction while retaining positive counts and formatted dates.

## Source evidence and supported analysis

Subtract one from day on each iteration. When the day drops below one, move to the previous month; wrapping January backward must first change the year and month to December of the previous year. Then determine that previous month's Gregorian length and set day to its last date. The leap-year test must use the year of the newly entered month. Keep the number of iterations equal to the original positive days, preserve the original captured date, and change only the printed operator from + to -. Typed input tuples remove row extraction without replacing the explicitly required manual calendar algorithm. Date libraries/functions remain prohibited by Task A.

Selected complete `main.qui` lines: 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26. All excerpt lines are verbatim and in source order. Ordinary language and documented package semantics apply. User-defined operations are supported by their selected statements when they are change dependencies; unaffected formatting helpers need no modification.

## Selection and measurement

The selected input/state bindings, bounds, decisions, arithmetic and output change sites support the requested answer. Unrelated unchanged source is omitted. The complete source and enclosing span are sufficient alternatives that add unrelated tokens. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Using unchanged `metric/tokenizer.py`: Task A **483** tokens; Task B **299** tokens. These are lexical evidence measurements and do not establish compilation or execution.

Measurement: Task A 483; Task B 299. Tokenizer: metric/tokenizer.py, unchanged.

The day-step range inherits int from days in the typed input tuple; its positive iteration count is unchanged.
