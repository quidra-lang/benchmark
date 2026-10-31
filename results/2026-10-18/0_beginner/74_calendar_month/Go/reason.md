# Task B selection: 74_calendar_month / Go

## Common answer requirements

Trace August 2026 first and last week-line construction from source weekday arithmetic; explain leading blanks, no trailing blank columns, two-character date fields, and one-space column separators.

## Supported analysis

For year 2026 and month 8 the shown weekday arithmetic yields 6 with Sunday column zero, so August 1 is Saturday. The first week contains six blank two-character fields followed by the two-character " 1" field: joining with six single separators yields nineteen leading spaces before 1. Implementations emitting characters directly produce the same width with weekday*3 leading spaces and the padded date. August has 31 days. The final printed week contains Sunday 30 and Monday 31, exactly "30 31" with no extra columns or trailing space. Each completed seven-field week is flushed/reset, and the residual week is printed at the last date without padding it to seven columns. Direct-output implementations emit a newline for the last date instead of another separator. Two-character width/pad operations and single-space joins/separators preserve formatting consistently.

The strings.Repeat prefix supplies start*3 spaces; the separator guard excludes the first day and Sunday starts, while the final-day newline adds no trailing blanks. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.go`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 11 | 56 | `	lengths := []int{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}` |
| 13 | 20 | `		y, m := p[0], p[1]` |
| 14 | 14 | `		yy, mm := y, m` |
| 15 | 12 | `		if mm < 3 {` |
| 16 | 10 | `			mm += 12` |
| 17 | 6 | `			yy--` |
| 18 | 4 | `		}` |
| 19 | 71 | `		h := (1 + 13*(mm+1)/5 + yy%100 + (yy%100)/4 + (yy/100)/4 + 5*(yy/100)) % 7` |
| 20 | 18 | `		start := (h + 6) % 7` |
| 21 | 13 | `		days := lengths[m-1]` |
| 28 | 60 | `		fmt.Printf("%s %d\nSu Mo Tu We Th Fr Sa\n%s", names[m-1], y, strings.Repeat(" ", start*3))` |
| 29 | 23 | `		for d := 1; d <= days; d++ {` |
| 30 | 23 | `			col := (start + d - 1) % 7` |
| 31 | 21 | `			if d > 1 && col > 0 {` |
| 32 | 13 | `				fmt.Print(" ")` |
| 33 | 5 | `			}` |
| 34 | 17 | `			fmt.Printf("%2d", d)` |
| 35 | 21 | `			if col == 6 \|\| d == days {` |
| 36 | 10 | `				fmt.Println()` |
| 37 | 5 | `			}` |
| 38 | 4 | `		}` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **426 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 668 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 441 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
