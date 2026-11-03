# Task B selection: 54_max_subarray / Ruby

## Common answer requirements

Trace array 2 through 10 and subsequent -2; explain restart versus extension and distinguish candidate-start state from the saved best range, including why a later candidate update can leave the recorded range unchanged.

## Supported analysis

For array 2, the running candidate/best evolves from -4/-4 to 7/7, 6/7, 9/9, 1/9, 11/11 at 10, then 9/11 at -2. Only the initial negative candidate restarts at the 7; the candidate at 10 extends the sum 1 and keeps that start. The best update copies the current start and current endpoint when the candidate strictly exceeds the saved sum. At -2 only the candidate sum falls to 9, so the recorded best stays 11 over zero-based [1,5]. Saved indices are scalar values, separate from the subsequently updated candidate state. A later restart likewise changes only candidate start unless a new strict maximum is found.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.rb`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 6 | `arrays = [` |
| 2 | 44 | `  [3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2],` |
| 3 | 55 | `  [-4, 7, -1, 3, -8, 10, -2, 5, -6, -2, 9, -12, 4, -1],` |
| 6 | 10 | `arrays.each do \|values\|` |
| 7 | 14 | `  current = best = values[0]` |
| 8 | 19 | `  start = best_start = best_end = 0` |
| 9 | 17 | `  (1...values.length).each do \|i\|` |
| 10 | 19 | `    if current + values[i] < values[i]` |
| 11 | 17 | `      current, start = values[i], i` |
| 12 | 3 | `    else` |
| 13 | 11 | `      current += values[i]` |
| 14 | 3 | `    end` |
| 15 | 31 | `    best, best_start, best_end = current, start, i if current > best` |
| 16 | 3 | `  end` |
| 18 | 2 | `end` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **254 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 344 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 256 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
