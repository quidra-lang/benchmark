# Task B selection: 57_matrix_determinant / Dart

## Common answer requirements

Identify every recursive cofactor expansion site; explain second-row coefficient and minor formation, parity reversal for one-based j, preserving the one-entry base case and integer arithmetic without modifying source.

## Supported analysis

Change the expansion coefficient from the first to the second row. Construct each minor from all rows except that second row and all columns except the chosen column, preserving the order of remaining rows and columns. In a zero-based column loop, add when the index is odd and subtract when it is even; in a one-based loop add for even j and subtract for odd j. The recursive call uses the same changed routine, so this applies at every size at least two. Keep the one-entry return and integer accumulation. For manually packed minors, replace r-1 indexing with a separate destination-row counter or an equivalent skip-aware mapping, since the retained rows now include the original first row. Original printing and fixtures are unaffected and supply no edit dependency.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.dart`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 16 | `int det(List<List<int>> matrix) {` |
| 2 | 24 | `  if (matrix.length == 1) return matrix[0][0];` |
| 3 | 10 | `  var result = 0;` |
| 4 | 28 | `  for (var j = 0; j < matrix.length; j++) {` |
| 5 | 9 | `    final minor = [` |
| 6 | 19 | `      for (final row in matrix.skip(1))` |
| 7 | 4 | `        [` |
| 8 | 28 | `          for (var c = 0; c < row.length; c++)` |
| 9 | 19 | `            if (c != j) row[c],` |
| 10 | 5 | `        ],` |
| 11 | 4 | `    ];` |
| 12 | 23 | `    final term = matrix[0][j] * det(minor);` |
| 13 | 25 | `    result += j % 2 == 0 ? term : -term;` |
| 14 | 3 | `  }` |
| 16 | 2 | `}` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **219 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 535 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 228 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
