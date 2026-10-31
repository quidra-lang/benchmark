# Task B selection: 50_roman_numerals / Lua

## Common answer requirements

Trace encoding of 1994 including the subtractive two-character entries; trace decoding with lookahead and signed contributions, explaining both remaining input and running total. Identify actual source operations supporting the trace.

## Supported analysis

The descending value/symbol table and repeated subtraction encode 1994 as M (remaining 994), CM (94), XC (4), IV (0). CM, XC, and IV are appended as complete two-character strings by the same loop. Decoding uses the single-symbol table and subtracts a current value when the following one is larger: M gives 1000; C subtracts 100 to 900; M adds 1000 to 1900; X subtracts 10 to 1890; C adds 100 to 1990; I subtracts 1 to 1989; V adds 5 to 1994. The last lookahead is zero or absent as shown. Both the mapping data and accumulator operations are needed; knowing the intended Roman numeral would not establish them.

 The question itself supplies 1994. Unrelated outer example enumeration is omitted; bind the per-value number/n to that focused input. Individual decoder entries for L/D are omitted where their complete lines are separately removable because neither character occurs in this trace. Alternative source set considered: focused-input enumeration plus the original per-value evidence, original lines 1,2,3,4,5,6,7,8,9,10,13,16,17,18,19,20,22,25,26,27, costs 539 tokens. The final selection costs 497 tokens. The removed context does not identify an additional requested edit/fact; any added scope or standard-binding evidence is necessary to establish the selected operations accurately. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.lua`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 11 | `local function to_roman(number)` |
| 2 | 10 | `    local result = ""` |
| 3 | 9 | `    local numerals = {` |
| 4 | 85 | `        {1000, "M"}, {900, "CM"}, {500, "D"}, {400, "CD"}, {100, "C"}, {90, "XC"}, {50, "L"},` |
| 5 | 64 | `        {40, "XL"}, {10, "X"}, {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"},` |
| 7 | 17 | `    for _, pair in ipairs(numerals) do` |
| 8 | 15 | `        while number >= pair[1] do` |
| 9 | 16 | `            result = result .. pair[2]` |
| 10 | 16 | `            number = number - pair[1]` |
| 11 | 4 | `        end` |
| 12 | 3 | `    end` |
| 13 | 5 | `    return result` |
| 14 | 2 | `end` |
| 16 | 11 | `local function from_roman(roman)` |
| 17 | 72 | `    local values, total = {I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000}, 0` |
| 18 | 15 | `    for i = 1, #roman do` |
| 19 | 21 | `        local value = values[roman:sub(i, i)]` |
| 20 | 55 | `        total = total + (i < #roman and value < values[roman:sub(i + 1, i + 1)] and -value or value)` |
| 21 | 3 | `    end` |
| 22 | 5 | `    return total` |
| 23 | 2 | `end` |
| 26 | 14 | `    local roman = to_roman(number)` |
| 27 | 42 | `    io.write(string.format("%d -> %s -> %d\n", number, roman, from_roman(roman)))` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **497 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 557 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 502 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
