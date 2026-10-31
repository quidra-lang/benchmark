# Task B selection: 56_permutations / Go

## Common answer requirements

Trace the recursive transition from the last A-prefix permutation to the first B-prefix one; explain partial-permutation lifetime, availability restoration using the actual representation, and the location and value of sequence numbering.

## Supported analysis

Increasing ABCD choice order yields ADCB as the last permutation beginning with A, numbered 6, then BACD as the first beginning with B, numbered 7. After the ADCB completion, the searches for ADC, AD, and A finish their remaining choices and return; each departing choice stops belonging to the active prefix. At the root the B branch can choose A, then C, then D. The excerpt shows whether this happens by immutable/string-value prefixes, explicit pop, depth-indexed overwrite, or copied availability arrays. The count is incremented only at length/depth four and its updated value is shared or returned as shown, so the next completion receives 7.

The [4]bool parameter is copied by value, while append passes a child slice with a longer length. Returning restores the caller slice length; caller explicitly clears its own used entry. The count pointer shares numbering. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.go`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 5 | 26 | `func search(p []byte, used [4]bool, count *int) {` |
| 6 | 14 | `	if len(p) == 4 {` |
| 7 | 8 | `		(*count)++` |
| 8 | 24 | `		fmt.Printf("%d: %s\n", *count, p)` |
| 9 | 4 | `		return` |
| 10 | 3 | `	}` |
| 11 | 22 | `	for i := 0; i < 4; i++ {` |
| 12 | 12 | `		if !used[i] {` |
| 13 | 12 | `			used[i] = true` |
| 14 | 27 | `			search(append(p, byte('A'+i)), used, count)` |
| 15 | 12 | `			used[i] = false` |
| 16 | 4 | `		}` |
| 17 | 3 | `	}` |
| 18 | 2 | `}` |
| 21 | 20 | `	search(nil, [4]bool{}, new(int))` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **193 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 216 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 195 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
