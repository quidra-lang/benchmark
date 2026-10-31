# Task B selection: 56_permutations / PHP

## Common answer requirements

Trace the recursive transition from the last A-prefix permutation to the first B-prefix one; explain partial-permutation lifetime, availability restoration using the actual representation, and the location and value of sequence numbering.

## Supported analysis

Increasing ABCD choice order yields ADCB as the last permutation beginning with A, numbered 6, then BACD as the first beginning with B, numbered 7. After the ADCB completion, the searches for ADC, AD, and A finish their remaining choices and return; each departing choice stops belonging to the active prefix. At the root the B branch can choose A, then C, then D. The excerpt shows whether this happens by immutable/string-value prefixes, explicit pop, depth-indexed overwrite, or copied availability arrays. The count is incremented only at length/depth four and its updated value is shared or returned as shown, so the next completion receives 7.

Array and string parameters have value semantics here; counter is explicitly passed by reference. The local used entry is reset for the next choice in that invocation. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.php`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 3 | 26 | `function visit(string $prefix, array $used, int &$counter): void` |
| 4 | 2 | `{` |
| 5 | 11 | `    $characters = 'ABCD';` |
| 6 | 17 | `    if (strlen($prefix) === 4) {` |
| 7 | 7 | `        $counter++;` |
| 8 | 24 | `        printf("%d: %s\n", $counter, $prefix);` |
| 9 | 5 | `        return;` |
| 10 | 3 | `    }` |
| 11 | 27 | `    for ($i = 0; $i < 4; $i++) {` |
| 12 | 16 | `        if (!$used[$i]) {` |
| 13 | 15 | `            $used[$i] = true;` |
| 14 | 27 | `            visit($prefix . $characters[$i], $used, $counter);` |
| 15 | 15 | `            $used[$i] = false;` |
| 16 | 4 | `        }` |
| 17 | 3 | `    }` |
| 18 | 2 | `}` |
| 20 | 8 | `$counter = 0;` |
| 21 | 25 | `visit('', array_fill(0, 4, false), $counter);` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **237 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 243 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 237 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
