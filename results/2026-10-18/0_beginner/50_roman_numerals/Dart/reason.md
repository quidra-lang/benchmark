# Task B selection: 50_roman_numerals / Dart

## Common answer requirements

Trace encoding of 1994 including the subtractive two-character entries; trace decoding with lookahead and signed contributions, explaining both remaining input and running total. Identify actual source operations supporting the trace.

## Supported analysis

The descending value/symbol table and repeated subtraction encode 1994 as M (remaining 994), CM (94), XC (4), IV (0). CM, XC, and IV are appended as complete two-character strings by the same loop. Decoding uses the single-symbol table and subtracts a current value when the following one is larger: M gives 1000; C subtracts 100 to 900; M adds 1000 to 1900; X subtracts 10 to 1890; C adds 100 to 1990; I subtracts 1 to 1989; V adds 5 to 1994. The last lookahead is zero or absent as shown. Both the mapping data and accumulator operations are needed; knowing the intended Roman numeral would not establish them.

 The question itself supplies 1994. Unrelated outer example enumeration is omitted; bind the per-value number/n to that focused input. Individual decoder entries for L/D are omitted where their complete lines are separately removable because neither character occurs in this trace. Alternative source set considered: focused-input enumeration plus the original per-value evidence, original lines 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,35,36,37,38,39, costs 501 tokens. The final selection costs 438 tokens. The removed context does not identify an additional requested edit/fact; any added scope or standard-binding evidence is necessary to establish the selected operations accurately. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.dart`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 2 | 9 | `  const pairs = [` |
| 3 | 14 | `    (1000, 'M'),` |
| 4 | 13 | `    (900, 'CM'),` |
| 5 | 13 | `    (500, 'D'),` |
| 6 | 13 | `    (400, 'CD'),` |
| 7 | 13 | `    (100, 'C'),` |
| 8 | 12 | `    (90, 'XC'),` |
| 9 | 12 | `    (50, 'L'),` |
| 10 | 12 | `    (40, 'XL'),` |
| 11 | 12 | `    (10, 'X'),` |
| 12 | 11 | `    (9, 'IX'),` |
| 13 | 11 | `    (5, 'V'),` |
| 14 | 11 | `    (4, 'IV'),` |
| 15 | 11 | `    (1, 'I'),` |
| 16 | 4 | `  ];` |
| 17 | 9 | `  const values = {` |
| 18 | 9 | `    'I': 1,` |
| 19 | 9 | `    'V': 5,` |
| 20 | 10 | `    'X': 10,` |
| 22 | 11 | `    'C': 100,` |
| 24 | 12 | `    'M': 1000,` |
| 25 | 4 | `  };` |
| 27 | 10 | `    var remaining = n;` |
| 28 | 13 | `    final buffer = StringBuffer();` |
| 29 | 15 | `    for (final p in pairs) {` |
| 30 | 16 | `      while (remaining >= p.$1) {` |
| 31 | 12 | `        buffer.write(p.$2);` |
| 32 | 11 | `        remaining -= p.$1;` |
| 33 | 4 | `      }` |
| 34 | 3 | `    }` |
| 35 | 15 | `    final roman = buffer.toString();` |
| 36 | 10 | `    var decoded = 0;` |
| 37 | 28 | `    for (var i = 0; i < roman.length; i++) {` |
| 38 | 17 | `      final v = values[roman[i]]!;` |
| 39 | 46 | `      decoded += i + 1 < roman.length && v < values[roman[i + 1]]! ? -v : v;` |
| 40 | 3 | `    }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **438 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 544 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 443 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
