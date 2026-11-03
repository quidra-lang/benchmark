# Task B selection: 59_date_add_days / C++

## Common answer requirements

Identify the day-stepping and month/year rollover logic and retained Gregorian length calculation; explain reversing movement across boundaries and changing the printed operator while keeping original positive count, input order, and padded dates.

## Supported analysis

Change each step to decrement the day. On reaching day zero, decrement the month; if it becomes zero, set month to December and decrement the year. Then set the day to the length of that new previous month, applying the shown Gregorian leap rule to the updated year/month. This ordering is necessary when stepping from March into February or January into the previous year. Retain the loop count and original positive n; change only the display operator from plus to minus. Keep date formatting and input iteration. In implementations computing the current month length before the step, move/recompute that calculation after selecting the previous month on rollover. The month-length helper can otherwise be reused.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.cpp`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 4 | 16 | `int days(int y, int m) {` |
| 5 | 62 | `    static constexpr int lengths[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};` |
| 6 | 67 | `    return lengths[m - 1] + (m == 2 && (y % 400 == 0 \|\| (y % 4 == 0 && y % 100 != 0)));` |
| 7 | 2 | `}` |
| 13 | 44 | `        int y = p[0], m = p[1], d = p[2], n = p[3];` |
| 14 | 27 | `        for (int i = 0; i < n; i++) {` |
| 15 | 7 | `            ++d;` |
| 16 | 21 | `            if (d > days(y, m)) {` |
| 17 | 11 | `                d = 1;` |
| 18 | 8 | `                ++m;` |
| 19 | 17 | `                if (m > 12) {` |
| 20 | 12 | `                    m = 1;` |
| 21 | 9 | `                    ++y;` |
| 22 | 6 | `                }` |
| 23 | 5 | `            }` |
| 24 | 4 | `        }` |
| 25 | 61 | `        std::cout << std::setfill('0') << std::setw(4) << p[0] << '-' << std::setw(2) << p[1] << '-'` |
| 26 | 69 | `            << std::setw(2) << p[2] << " + " << n << " days = " << std::setw(4) << y << '-' << std::setw(2)` |
| 27 | 34 | `            << m << '-' << std::setw(2) << d << '\n';` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **482 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 648 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 487 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
