# Task B selection: 59_date_add_days / PHP

## Common answer requirements

Identify the day-stepping and month/year rollover logic and retained Gregorian length calculation; explain reversing movement across boundaries and changing the printed operator while keeping original positive count, input order, and padded dates.

## Supported analysis

Change each step to decrement the day. On reaching day zero, decrement the month; if it becomes zero, set month to December and decrement the year. Then set the day to the length of that new previous month, applying the shown Gregorian leap rule to the updated year/month. This ordering is necessary when stepping from March into February or January into the previous year. Retain the loop count and original positive n; change only the display operator from plus to minus. Keep date formatting and input iteration. In implementations computing the current month length before the step, move/recompute that calculation after selecting the previous month on rollover. The month-length helper can otherwise be reused.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.php`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 3 | 21 | `function daysInMonth(int $year, int $month): int` |
| 4 | 2 | `{` |
| 5 | 50 | `    $leap = $year % 400 === 0 \|\| ($year % 4 === 0 && $year % 100 !== 0);` |
| 6 | 80 | `    return $month === 2 && $leap ? 29 : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][$month - 1];` |
| 7 | 2 | `}` |
| 14 | 38 | `    [$year, $month, $day] = array_map('intval', explode('-', $original));` |
| 15 | 28 | `    for ($step = 0; $step < $added; $step++) {` |
| 16 | 7 | `        $day++;` |
| 17 | 25 | `        if ($day > daysInMonth($year, $month)) {` |
| 18 | 11 | `            $day = 1;` |
| 19 | 8 | `            $month++;` |
| 20 | 17 | `            if ($month > 12) {` |
| 21 | 12 | `                $month = 1;` |
| 22 | 9 | `                $year++;` |
| 23 | 5 | `            }` |
| 24 | 4 | `        }` |
| 25 | 3 | `    }` |
| 26 | 50 | `    printf("%s + %d days = %04d-%02d-%02d\n", $original, $added, $year, $month, $day);` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **372 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 514 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 377 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
