# Task B selection: 50_roman_numerals / C

## Common answer requirements

Trace encoding of 1994 including the subtractive two-character entries; trace decoding with lookahead and signed contributions, explaining both remaining input and running total. Identify actual source operations supporting the trace.

## Supported analysis

The descending value/symbol table and repeated subtraction encode 1994 as M (remaining 994), CM (94), XC (4), IV (0). CM, XC, and IV are appended as complete two-character strings by the same loop. Decoding uses the single-symbol table and subtracts a current value when the following one is larger: M gives 1000; C subtracts 100 to 900; M adds 1000 to 1900; X subtracts 10 to 1890; C adds 100 to 1990; I subtracts 1 to 1989; V adds 5 to 1994. The last lookahead is zero or absent as shown. Both the mapping data and accumulator operations are needed; knowing the intended Roman numeral would not establish them.

The switch needs only I, C, M, and its default-zero case: these are the decoded characters and the terminating NUL used for final lookahead; X and V are also required and their cases are selected. The question itself supplies 1994. Unrelated outer example enumeration is omitted; bind the per-value number/n to that focused input. Individual decoder entries for L/D are omitted where their complete lines are separately removable because neither character occurs in this trace. Alternative source set considered: focused-input enumeration plus the original per-value evidence, original lines 4,5,6,7,8,10,12,13,18,19,20,21,22,23,24,25,26,27,29,30,31,32, costs 521 tokens. The final selection costs 461 tokens. The removed context does not identify an additional requested edit/fact; any added scope or standard-binding evidence is necessary to establish the selected operations accurately. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.c`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 4 | 11 | `int value(char c) {` |
| 5 | 9 | `    switch (c) {` |
| 6 | 14 | `        case 'I': return 1;` |
| 7 | 14 | `        case 'V': return 5;` |
| 8 | 15 | `        case 'X': return 10;` |
| 10 | 16 | `        case 'C': return 100;` |
| 12 | 17 | `        case 'M': return 1000;` |
| 13 | 10 | `        default: return 0;` |
| 14 | 3 | `    }` |
| 15 | 2 | `}` |
| 19 | 64 | `    int values[] = {1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1};` |
| 20 | 78 | `    const char *symbols[] = {"M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"};` |
| 22 | 14 | `        int remaining = numbers[k];` |
| 23 | 16 | `        char roman[64] = "";` |
| 24 | 26 | `        for (int i = 0; i < 13; i++)` |
| 25 | 18 | `            while (remaining >= values[i]) {` |
| 26 | 16 | `                strcat(roman, symbols[i]);` |
| 27 | 14 | `                remaining -= values[i];` |
| 28 | 5 | `            }` |
| 29 | 11 | `        int result = 0;` |
| 30 | 26 | `        for (int i = 0; roman[i]; i++) {` |
| 31 | 35 | `            int v = value(roman[i]), next = value(roman[i + 1]);` |
| 32 | 23 | `            result += v < next ? -v : v;` |
| 33 | 4 | `        }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **461 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 641 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 466 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
