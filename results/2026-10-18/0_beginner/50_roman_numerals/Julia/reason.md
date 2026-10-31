# Task B selection: 50_roman_numerals / Julia

## Common answer requirements

Trace encoding of 1994 including the subtractive two-character entries; trace decoding with lookahead and signed contributions, explaining both remaining input and running total. Identify actual source operations supporting the trace.

## Supported analysis

The descending value/symbol table and repeated subtraction encode 1994 as M (remaining 994), CM (94), XC (4), IV (0). CM, XC, and IV are appended as complete two-character strings by the same loop. Decoding uses the single-symbol table and subtracts a current value when the following one is larger: M gives 1000; C subtracts 100 to 900; M adds 1000 to 1900; X subtracts 10 to 1890; C adds 100 to 1990; I subtracts 1 to 1989; V adds 5 to 1994. The last lookahead is zero or absent as shown. Both the mapping data and accumulator operations are needed; knowing the intended Roman numeral would not establish them.

 The question itself supplies 1994. Unrelated outer example enumeration is omitted; bind the per-value number/n to that focused input. Individual decoder entries for L/D are omitted where their complete lines are separately removable because neither character occurs in this trace. Alternative source set considered: focused-input enumeration plus the original per-value evidence, original lines 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,23,26,27,28,29,30,31,33,36,37,38, costs 478 tokens. The final selection costs 444 tokens. The removed context does not identify an additional requested edit/fact; any added scope or standard-binding evidence is necessary to establish the selected operations accurately. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.jl`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 9 | `function to_roman(number)` |
| 2 | 8 | `    result = ""` |
| 3 | 14 | `    for (value, symbol) in [` |
| 4 | 15 | `        (1000, "M"),` |
| 5 | 14 | `        (900, "CM"),` |
| 6 | 14 | `        (500, "D"),` |
| 7 | 14 | `        (400, "CD"),` |
| 8 | 14 | `        (100, "C"),` |
| 9 | 13 | `        (90, "XC"),` |
| 10 | 13 | `        (50, "L"),` |
| 11 | 13 | `        (40, "XL"),` |
| 12 | 13 | `        (10, "X"),` |
| 13 | 12 | `        (9, "IX"),` |
| 14 | 12 | `        (5, "V"),` |
| 15 | 12 | `        (4, "IV"),` |
| 16 | 12 | `        (1, "I"),` |
| 18 | 10 | `        while number >= value` |
| 19 | 9 | `            result *= symbol` |
| 20 | 9 | `            number -= value` |
| 21 | 4 | `        end` |
| 22 | 3 | `    end` |
| 23 | 5 | `    return result` |
| 24 | 2 | `end` |
| 26 | 9 | `function from_roman(roman)` |
| 27 | 65 | `    table = Dict('I'=>1, 'V'=>5, 'X'=>10, 'L'=>50, 'C'=>100, 'D'=>500, 'M'=>1000)` |
| 28 | 7 | `    total = 0` |
| 29 | 14 | `    for i = 1:length(roman)` |
| 30 | 13 | `        value = table[roman[i]]` |
| 31 | 39 | `        total += i < length(roman) && value < table[roman[i+1]] ? -value : value` |
| 32 | 3 | `    end` |
| 33 | 5 | `    return total` |
| 34 | 2 | `end` |
| 37 | 12 | `    roman = to_roman(number)` |
| 38 | 31 | `    println(number, " -> ", roman, " -> ", from_roman(roman))` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **444 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 496 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 449 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
