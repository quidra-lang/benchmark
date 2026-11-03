# Task B selection: 63_word_search / Dart

## Common answer requirements

Identify all first-match exits and output/result state; explain preserving row-major cells and E,SE,S,SW,W,NW,N,NE direction order, visiting all valid matches, retaining the final match or not-found fallback in the current per-word format.

## Supported analysis

Keep the shown increasing row/column/direction traversal. Replace first-success return/break with overwriting a saved result for each successful match; finish all search loops before returning or printing it. Remove found-based loop guards and all success exits that suppress later combinations. Keep the character-mismatch break inside the match test, because it rejects only the current candidate. Initialize the saved result to the existing not-found value, or retain a separate any-match flag and saved coordinates/direction. For implementations that print directly on success, move that print after the loops and print only the last saved tuple, falling back to not found when none was saved. The actual grid and word fixtures and unchanged match predicate internals are not needed to identify these edits.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.dart`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 24 | 49 | `  const names = ['E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE'];` |
| 26 | 10 | `    var found = false;` |
| 27 | 4 | `    search:` |
| 28 | 27 | `    for (var r = 0; r < 10; r++) {` |
| 29 | 28 | `      for (var c = 0; c < 10; c++) {` |
| 30 | 27 | `        for (var d = 0; d < 8; d++) {` |
| 43 | 11 | `          if (matches) {` |
| 44 | 30 | `            print('$word: ($r, $c) ${names[d]}');` |
| 45 | 10 | `            found = true;` |
| 46 | 8 | `            break search;` |
| 47 | 5 | `          }` |
| 48 | 4 | `        }` |
| 49 | 4 | `      }` |
| 50 | 3 | `    }` |
| 51 | 22 | `    if (!found) print('$word: not found');` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **242 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 652 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 265 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
