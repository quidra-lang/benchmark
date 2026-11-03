# Task B selection: 57_matrix_determinant / Zig

## Common answer requirements

Identify every recursive cofactor expansion site; explain second-row coefficient and minor formation, parity reversal for one-based j, preserving the one-entry base case and integer arithmetic without modifying source.

## Supported analysis

Change the expansion coefficient from the first to the second row. Construct each minor from all rows except that second row and all columns except the chosen column, preserving the order of remaining rows and columns. In a zero-based column loop, add when the index is odd and subtract when it is even; in a one-based loop add for even j and subtract for odd j. The recursive call uses the same changed routine, so this applies at every size at least two. Keep the one-entry return and integer accumulation. For manually packed minors, replace r-1 indexing with a separate destination-row counter or an equivalent skip-aware mapping, since the retained rows now include the original first row. Original printing and fixtures are unaffected and supply no edit dependency.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.zig`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 3 | 28 | `fn det(comptime n: usize, matrix: [n][n]i64) i64 {` |
| 4 | 13 | `    if (n == 1) {` |
| 5 | 13 | `        return matrix[0][0];` |
| 6 | 7 | `    } else {` |
| 7 | 14 | `        var result: i64 = 0;` |
| 8 | 16 | `        for (0..n) \|j\| {` |
| 9 | 29 | `            var minor: [n - 1][n - 1]i64 = undefined;` |
| 10 | 17 | `            for (1..n) \|r\| {` |
| 11 | 16 | `                var col: usize = 0;` |
| 12 | 18 | `                for (0..n) \|c\| {` |
| 13 | 17 | `                    if (c != j) {` |
| 14 | 29 | `                        minor[r - 1][col] = matrix[r][c];` |
| 15 | 13 | `                        col += 1;` |
| 16 | 7 | `                    }` |
| 17 | 6 | `                }` |
| 18 | 5 | `            }` |
| 19 | 32 | `            const term = matrix[0][j] * det(n - 1, minor);` |
| 20 | 29 | `            result += if (j % 2 == 0) term else -term;` |
| 21 | 4 | `        }` |
| 23 | 3 | `    }` |
| 24 | 2 | `}` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **318 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 842 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 332 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
