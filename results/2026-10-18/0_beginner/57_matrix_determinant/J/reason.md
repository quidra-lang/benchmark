# Task B selection: 57_matrix_determinant / J

## Common answer requirements

Identify every recursive cofactor expansion site; explain second-row coefficient and minor formation, parity reversal for one-based j, preserving the one-entry base case and integer arithmetic without modifying source.

## Supported analysis

Change the expansion coefficient from the first to the second row. Construct each minor from all rows except that second row and all columns except the chosen column, preserving the order of remaining rows and columns. In a zero-based column loop, add when the index is odd and subtract when it is even; in a one-based loop add for even j and subtract for odd j. The recursive call uses the same changed routine, so this applies at every size at least two. Keep the one-entry return and integer accumulation. For manually packed minors, replace r-1 indexing with a separate destination-row counter or an equivalent skip-aware mapping, since the retained rows now include the original first row. Original printing and fixtures are unaffected and supply no edit dependency.

}.y currently drops the first row; filter the row index vector to exclude 1 instead, select coefficient row 1, and invert the zero-based parity branch. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.ijs`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 10 | `determinant =: 3 : 0` |
| 2 | 8 | `  n =. #y` |
| 3 | 22 | `  if. n=1 do. (<0 0){y return. end.` |
| 4 | 7 | `  total =. 0` |
| 5 | 12 | `  for_j. i.n do.` |
| 6 | 20 | `    minor =. (j~:i.n) #"1 }.y` |
| 7 | 17 | `    term =. (j{0{y)*determinant minor` |
| 8 | 19 | `    if. 0=2\|j do. total =. total+term` |
| 9 | 11 | `    else. total =. total-term` |
| 10 | 3 | `    end.` |
| 11 | 3 | `  end.` |
| 13 | 2 | `)` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **134 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 368 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 139 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
