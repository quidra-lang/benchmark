# Task B selection: 74_calendar_month / Quidra

## Common answer requirements

Trace August 2026 first and last week-line construction from source weekday arithmetic; explain leading blanks, no trailing blank columns, two-character date fields, and one-space column separators.

## Supported analysis

For year 2026 and month 8 the shown weekday arithmetic yields 6 with Sunday column zero, so August 1 is Saturday. The first week contains six blank two-character fields followed by the two-character " 1" field: joining with six single separators yields nineteen leading spaces before 1. Implementations emitting characters directly produce the same width with weekday*3 leading spaces and the padded date. August has 31 days. The final printed week contains Sunday 30 and Monday 31, exactly "30 31" with no extra columns or trailing space. Each completed seven-field week is flushed/reset, and the residual week is printed at the last date without padding it to seven columns. Direct-output implementations emit a newline for the last date instead of another separator. Two-character width/pad operations and single-space joins/separators preserve formatting consistently.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.qui`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 5 | 56 | `int[] lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]` |
| 8 | 15 | `    int year = months[index][0]` |
| 9 | 15 | `    int month = months[index][1]` |
| 10 | 9 | `    int y = year` |
| 11 | 9 | `    int m = month` |
| 12 | 9 | `    if m < 3` |
| 13 | 9 | `        m += 12` |
| 14 | 8 | `        y -= 1` |
| 15 | 15 | `    int century = y / 100` |
| 16 | 15 | `    int within = y % 100` |
| 17 | 62 | `    int h = (1 + 13 * (m + 1) / 5 + within + within / 4 + century / 4 + 5 * century) % 7` |
| 18 | 19 | `    int weekday = (h + 6) % 7` |
| 19 | 16 | `    int days = lengths[month - 1]` |
| 24 | 40 | `    print("{names[month - 1]} {year}{NL}Su Mo Tu We Th Fr Sa{NL}")` |
| 25 | 26 | `    string line = string.repeat(" ", nat(weekday * 3))` |
| 26 | 9 | `    int column = weekday` |
| 27 | 15 | `    for 1 <= int day <= days` |
| 28 | 18 | `        if day > 1 and column > 0` |
| 29 | 11 | `            line += " "` |
| 30 | 16 | `        line += "{day:int=2}"` |
| 31 | 8 | `        column += 1` |
| 32 | 18 | `        if column == 7 or day == days` |
| 33 | 12 | `            print(line + NL)` |
| 34 | 10 | `            line = ""` |
| 35 | 9 | `            column = 0` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **449 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 655 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 451 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
