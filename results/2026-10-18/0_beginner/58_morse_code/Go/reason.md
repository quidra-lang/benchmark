# Task B selection: 58_morse_code / Go

## Common answer requirements

Identify the generated-Morse-to-message data path; trace the first ME / AT boundary, distinguishing letter and word separators; identify mapping and generated separator information supplying decoded letters/spaces and establish reconstruction without reading original-message characters.

## Supported analysis

At the ME-to-AT boundary the generated text is "-- . / .- -": spaces separate letter codes, while the slash marker (normally framed by spaces) separates words. Decoding resolves -- to M and . to E, then creates one decoded space from the word boundary, followed by .- to A and - to T. The table/alphabet or reverse map provides letters; the generated boundary supplies spaces. The decode path consumes encoded text, not characters from message. Nested word/letter split implementations split " / " first, split each word on spaces, concatenate letters, and join decoded words with spaces. Token-stream implementations split on spaces and handle the standalone slash token specially. The selected encoder separator operations establish where that distinction is generated.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.go`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 10 | 9 | `	symbols := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"` |
| 11 | 71 | `	codes := []string{".-", "-...", "-.-.", "-..", ".", "..-.", "--.", "....", "..", ".---", "-.-",` |
| 12 | 82 | `		".-..", "--", "-.", "---", ".--.", "--.-", ".-.", "...", "-", "..-", "...-", ".--", "-..-", "-.--",` |
| 13 | 73 | `		"--..", "-----", ".----", "..---", "...--", "....-", ".....", "-....", "--...", "---..", "----."}` |
| 14 | 24 | `	message := "MEET ME AT PIER 9 AT 1745"` |
| 15 | 10 | `	words := []string{}` |
| 16 | 26 | `	for _, w := range strings.Split(message, " ") {` |
| 17 | 11 | `		parts := []string{}` |
| 18 | 17 | `		for _, c := range w {` |
| 19 | 27 | `			parts = append(parts, codes[strings.IndexRune(symbols, c)])` |
| 20 | 4 | `		}` |
| 21 | 24 | `		words = append(words, strings.Join(parts, " "))` |
| 22 | 3 | `	}` |
| 23 | 19 | `	encoded := strings.Join(words, " / ")` |
| 25 | 10 | `	decoded := []string{}` |
| 26 | 28 | `	for _, w := range strings.Split(encoded, " / ") {` |
| 27 | 9 | `		word := ""` |
| 28 | 27 | `		for _, token := range strings.Split(w, " ") {` |
| 29 | 23 | `			word += string(symbols[slices.Index(codes, token)])` |
| 30 | 4 | `		}` |
| 31 | 14 | `		decoded = append(decoded, word)` |
| 32 | 3 | `	}` |
| 33 | 18 | `	fmt.Println(strings.Join(decoded, " "))` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **536 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 581 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 540 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
