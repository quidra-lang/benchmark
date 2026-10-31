# Task B selection: 59_date_add_days / Rust

## Common answer requirements

Identify the day-stepping and month/year rollover logic and retained Gregorian length calculation; explain reversing movement across boundaries and changing the printed operator while keeping original positive count, input order, and padded dates.

## Supported analysis

Change each step to decrement the day. On reaching day zero, decrement the month; if it becomes zero, set month to December and decrement the year. Then set the day to the length of that new previous month, applying the shown Gregorian leap rule to the updated year/month. This ordering is necessary when stepping from March into February or January into the previous year. Retain the loop count and original positive n; change only the display operator from plus to minus. Keep date formatting and input iteration. In implementations computing the current month length before the step, move/recompute that calculation after selecting the previous month on rollover. The month-length helper can otherwise be reused.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.rs`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 22 | `fn days(y: i32, m: i32) -> i32 {` |
| 2 | 57 | `    let lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];` |
| 3 | 73 | `    lengths[(m - 1) as usize] + i32::from(m == 2 && (y % 400 == 0 \|\| (y % 4 == 0 && y % 100 != 0)))` |
| 4 | 2 | `}` |
| 14 | 33 | `        let (mut y, mut m, mut d) = (y0, m0, d0);` |
| 15 | 14 | `        for _ in 0..n {` |
| 16 | 10 | `            d += 1;` |
| 17 | 19 | `            if d > days(y, m) {` |
| 18 | 11 | `                d = 1;` |
| 19 | 11 | `                m += 1;` |
| 20 | 15 | `                if m > 12 {` |
| 21 | 12 | `                    m = 1;` |
| 22 | 12 | `                    y += 1;` |
| 23 | 6 | `                }` |
| 24 | 5 | `            }` |
| 25 | 4 | `        }` |
| 26 | 6 | `        println!(` |
| 27 | 45 | `            "{:04}-{:02}-{:02} + {} days = {:04}-{:02}-{:02}",` |
| 28 | 23 | `            y0, m0, d0, n, y, m, d` |
| 29 | 5 | `        );` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **385 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 534 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 390 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
