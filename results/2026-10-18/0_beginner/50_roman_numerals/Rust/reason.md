# Task B selection: 50_roman_numerals / Rust

## Common answer requirements

Trace encoding of 1994 including the subtractive two-character entries; trace decoding with lookahead and signed contributions, explaining both remaining input and running total. Identify actual source operations supporting the trace.

## Supported analysis

The descending value/symbol table and repeated subtraction encode 1994 as M (remaining 994), CM (94), XC (4), IV (0). CM, XC, and IV are appended as complete two-character strings by the same loop. Decoding uses the single-symbol table and subtracts a current value when the following one is larger: M gives 1000; C subtracts 100 to 900; M adds 1000 to 1900; X subtracts 10 to 1890; C adds 100 to 1990; I subtracts 1 to 1989; V adds 5 to 1994. The last lookahead is zero or absent as shown. Both the mapping data and accumulator operations are needed; knowing the intended Roman numeral would not establish them.

The byte conversion and map_or lookahead establish that absent next bytes contribute zero. The question itself supplies 1994. Unrelated outer example enumeration is omitted; bind the per-value number/n to that focused input. Individual decoder entries for L/D are omitted where their complete lines are separately removable because neither character occurs in this trace. Alternative source set considered: focused-input enumeration plus the original per-value evidence, original lines 1,2,3,4,5,7,9,15,16,17,18,19,20,21,22,23,24,25,28,29,30,31,32,33, costs 508 tokens. The final selection costs 478 tokens. The removed context does not identify an additional requested edit/fact; any added scope or standard-binding evidence is necessary to establish the selected operations accurately. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.rs`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 16 | `fn value(c: u8) -> i32 {` |
| 2 | 7 | `    match c {` |
| 3 | 12 | `        b'I' => 1,` |
| 4 | 12 | `        b'V' => 5,` |
| 5 | 13 | `        b'X' => 10,` |
| 7 | 14 | `        b'C' => 100,` |
| 9 | 15 | `        b'M' => 1000,` |
| 11 | 3 | `    }` |
| 12 | 2 | `}` |
| 15 | 63 | `    let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];` |
| 16 | 9 | `    let symbols = [` |
| 17 | 67 | `        "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I",` |
| 18 | 4 | `    ];` |
| 20 | 13 | `        let mut remaining = n;` |
| 21 | 17 | `        let mut roman = String::new();` |
| 22 | 15 | `        for i in 0..13 {` |
| 23 | 16 | `            while remaining >= values[i] {` |
| 24 | 17 | `                roman.push_str(symbols[i]);` |
| 25 | 14 | `                remaining -= values[i];` |
| 26 | 5 | `            }` |
| 27 | 4 | `        }` |
| 28 | 17 | `        let bytes = roman.as_bytes();` |
| 29 | 13 | `        let mut result = 0;` |
| 30 | 18 | `        for i in 0..bytes.len() {` |
| 31 | 18 | `            let v = value(bytes[i]);` |
| 32 | 39 | `            let next = bytes.get(i + 1).map_or(0, \|&c\| value(c));` |
| 33 | 31 | `            result += if v < next { -v } else { v };` |
| 34 | 4 | `        }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **478 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 607 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 483 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
