# Task B selection: 57_matrix_determinant / Go

## Common answer requirements

Identify every recursive cofactor expansion site; explain second-row coefficient and minor formation, parity reversal for one-based j, preserving the one-entry base case and integer arithmetic without modifying source.

## Supported analysis

Change the expansion coefficient from the first to the second row. Construct each minor from all rows except that second row and all columns except the chosen column, preserving the order of remaining rows and columns. In a zero-based column loop, add when the index is odd and subtract when it is even; in a one-based loop add for even j and subtract for odd j. The recursive call uses the same changed routine, so this applies at every size at least two. Keep the one-entry return and integer accumulation. For manually packed minors, replace r-1 indexing with a separate destination-row counter or an equivalent skip-aware mapping, since the retained rows now include the original first row. Original printing and fixtures are unaffected and supply no edit dependency.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.go`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 5 | 15 | `func det(a [][]int) int {` |
| 6 | 14 | `	if len(a) == 1 {` |
| 7 | 12 | `		return a[0][0]` |
| 8 | 3 | `	}` |
| 9 | 7 | `	result := 0` |
| 10 | 13 | `	for j := range a {` |
| 11 | 12 | `		minor := [][]int{}` |
| 12 | 21 | `		for _, r := range a[1:] {` |
| 13 | 12 | `			row := []int{}` |
| 14 | 18 | `			for c, v := range r {` |
| 15 | 14 | `				if c != j {` |
| 16 | 17 | `					row = append(row, v)` |
| 17 | 6 | `				}` |
| 18 | 5 | `			}` |
| 19 | 15 | `			minor = append(minor, row)` |
| 20 | 4 | `		}` |
| 21 | 21 | `		term := a[0][j] * det(minor)` |
| 22 | 14 | `		if j%2 == 0 {` |
| 23 | 9 | `			result += term` |
| 24 | 8 | `		} else {` |
| 25 | 9 | `			result -= term` |
| 26 | 4 | `		}` |
| 27 | 3 | `	}` |
| 29 | 2 | `}` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **258 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 560 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 266 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
