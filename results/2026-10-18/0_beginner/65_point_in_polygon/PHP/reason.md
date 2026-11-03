# Task B selection: 65_point_in_polygon / PHP

## Common answer requirements

Locate ray-crossing state, strict crossing conditions, parity classification and output; explain reporting a nonnegative count from exactly those conditions and appending one space plus crossings=N without changing point order/coordinates.

## Supported analysis

Where the program toggles a boolean inside flag, replace that state with an integer initialized to zero and increment at precisely the current toggle site, under both strict tests: endpoint heights straddle py using >, and the intersection is strictly to the right of px. Derive inside from an odd count and outside from an even count; do not count any other edge or run a second differently-filtered traversal. Where the program already accumulates crossings, reuse it directly. Append " crossings=" and the ordinary decimal integer value after the classification in the existing output expression. The selected state, guards, classification and output establish all affected dependencies; polygon and point fixture literals are unchanged.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.php`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 5 | 9 | `    $crossings = 0;` |
| 8 | 30 | `        if (($y1 > $py) !== ($y2 > $py)) {` |
| 9 | 48 | `            $intersection = $x1 + ($x2 - $x1) * ($py - $y1) / ($y2 - $y1);` |
| 10 | 17 | `            if ($intersection > $px) {` |
| 11 | 9 | `                $crossings++;` |
| 12 | 5 | `            }` |
| 13 | 4 | `        }` |
| 15 | 54 | `    printf("(%d, %d): %s\n", $px, $py, $crossings % 2 === 1 ? 'inside' : 'outside');` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **176 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 388 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 181 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
