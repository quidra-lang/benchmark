# Task B selection: 50_roman_numerals / Go

## Common answer requirements

Trace encoding of 1994 including the subtractive two-character entries; trace decoding with lookahead and signed contributions, explaining both remaining input and running total. Identify actual source operations supporting the trace.

## Supported analysis

The descending value/symbol table and repeated subtraction encode 1994 as M (remaining 994), CM (94), XC (4), IV (0). CM, XC, and IV are appended as complete two-character strings by the same loop. Decoding uses the single-symbol table and subtracts a current value when the following one is larger: M gives 1000; C subtracts 100 to 900; M adds 1000 to 1900; X subtracts 10 to 1890; C adds 100 to 1990; I subtracts 1 to 1989; V adds 5 to 1994. The last lookahead is zero or absent as shown. Both the mapping data and accumulator operations are needed; knowing the intended Roman numeral would not establish them.

 The question itself supplies 1994. Unrelated outer example enumeration is omitted; bind the per-value number/n to that focused input. Individual decoder entries for L/D are omitted where their complete lines are separately removable because neither character occurs in this trace. Alternative source set considered: focused-input enumeration plus the original per-value evidence, original lines 5,6,7,8,15,16,19,20,22,26,27,28,29,30,31,32,33,34,37,38,39,40,41,43,44,45,46, costs 453 tokens. The final selection costs 450 tokens. The removed context does not identify an additional requested edit/fact; any added scope or standard-binding evidence is necessary to establish the selected operations accurately. The helper default return0 is not reached by any decoded symbol; guarded lookahead already initializes next to0. The unused fallback line is therefore omitted. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.go`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 5 | 13 | `func value(c byte) int {` |
| 6 | 7 | `	switch c {` |
| 7 | 8 | `	case 'I':` |
| 8 | 6 | `		return 1` |
| 9 | 8 | `	case 'V':` |
| 10 | 6 | `		return 5` |
| 11 | 8 | `	case 'X':` |
| 12 | 7 | `		return 10` |
| 15 | 8 | `	case 'C':` |
| 16 | 8 | `		return 100` |
| 19 | 8 | `	case 'M':` |
| 20 | 9 | `		return 1000` |
| 21 | 3 | `	}` |
| 23 | 2 | `}` |
| 26 | 62 | `	values := []int{1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1}` |
| 27 | 73 | `	symbols := []string{"M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"}` |
| 29 | 8 | `		remaining := n` |
| 30 | 9 | `		roman := ""` |
| 31 | 17 | `		for i, v := range values {` |
| 32 | 13 | `			for remaining >= v {` |
| 33 | 13 | `				roman += symbols[i]` |
| 34 | 10 | `				remaining -= v` |
| 35 | 5 | `			}` |
| 36 | 4 | `		}` |
| 37 | 8 | `		result := 0` |
| 38 | 14 | `		for i := range roman {` |
| 39 | 21 | `			v, next := value(roman[i]), 0` |
| 40 | 18 | `			if i+1 < len(roman) {` |
| 41 | 18 | `				next = value(roman[i+1])` |
| 42 | 5 | `			}` |
| 43 | 13 | `			if v < next {` |
| 44 | 10 | `				result -= v` |
| 45 | 9 | `			} else {` |
| 46 | 10 | `				result += v` |
| 47 | 5 | `			}` |
| 48 | 4 | `		}` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **450 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 600 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 455 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
