# Task B selection: 58_morse_code / Lua

## Common answer requirements

Identify the generated-Morse-to-message data path; trace the first ME / AT boundary, distinguishing letter and word separators; identify mapping and generated separator information supplying decoded letters/spaces and establish reconstruction without reading original-message characters.

## Supported analysis

At the ME-to-AT boundary the generated text is "-- . / .- -": spaces separate letter codes, while the slash marker (normally framed by spaces) separates words. Decoding resolves -- to M and . to E, then creates one decoded space from the word boundary, followed by .- to A and - to T. The table/alphabet or reverse map provides letters; the generated boundary supplies spaces. The decode path consumes encoded text, not characters from message. Nested word/letter split implementations split " / " first, split each word on spaces, concatenate letters, and join decoded words with spaces. Token-stream implementations split on spaces and handle the standalone slash token specially. The selected encoder separator operations establish where that distinction is generated.

The decode outer [^/]+ pattern separates at slash; %S+ ignores the surrounding whitespace and yields each letter code. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.lua`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 10 | `local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"` |
| 2 | 114 | `local codes = ".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----."` |
| 3 | 24 | `local mapping, reverse_mapping, index = {}, {}, 1` |
| 4 | 19 | `for code in codes:gmatch("%S+") do` |
| 5 | 17 | `    local letter = alphabet:sub(index, index)` |
| 6 | 10 | `    mapping[letter] = code` |
| 7 | 12 | `    reverse_mapping[code] = letter` |
| 8 | 11 | `    index = index + 1` |
| 9 | 2 | `end` |
| 10 | 9 | `local words = {}` |
| 11 | 38 | `for word in ("MEET ME AT PIER 9 AT 1745"):gmatch("%S+") do` |
| 12 | 10 | `    local letters = {}` |
| 13 | 37 | `    for letter in word:gmatch(".") do letters[#letters + 1] = mapping[letter] end` |
| 14 | 25 | `    words[#words + 1] = table.concat(letters, " ")` |
| 15 | 2 | `end` |
| 16 | 20 | `local encoded = table.concat(words, " / ")` |
| 17 | 11 | `local decoded_words = {}` |
| 18 | 21 | `for word in encoded:gmatch("[^/]+") do` |
| 19 | 10 | `    local letters = {}` |
| 20 | 41 | `    for code in word:gmatch("%S+") do letters[#letters + 1] = reverse_mapping[code] end` |
| 21 | 24 | `    decoded_words[#decoded_words + 1] = table.concat(letters)` |
| 22 | 2 | `end` |
| 23 | 34 | `io.write(encoded, "\n", table.concat(decoded_words, " "), "\n")` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **503 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 503 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 503 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
