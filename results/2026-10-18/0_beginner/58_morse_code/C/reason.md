# Task B selection: 58_morse_code / C

## Common answer requirements

Identify the generated-Morse-to-message data path; trace the first ME / AT boundary, distinguishing letter and word separators; identify mapping and generated separator information supplying decoded letters/spaces and establish reconstruction without reading original-message characters.

## Supported analysis

At the ME-to-AT boundary the generated text is "-- . / .- -": spaces separate letter codes, while the slash marker (normally framed by spaces) separates words. Decoding resolves -- to M and . to E, then creates one decoded space from the word boundary, followed by .- to A and - to T. The table/alphabet or reverse map provides letters; the generated boundary supplies spaces. The decode path consumes encoded text, not characters from message. Nested word/letter split implementations split " / " first, split each word on spaces, concatenate letters, and join decoded words with spaces. Token-stream implementations split on spaces and handle the standalone slash token specially. The selected encoder separator operations establish where that distinction is generated.

strtok mutates encoded into space-delimited tokens. strcmp(token,"/") creates a decoded space; other tokens search codes and use the matching alphabet index. Original message appears only in the encoder path. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.c`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 5 | 39 | `    const char *symbols = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", *codes[] = {".-", "-...", "-.-.",` |
| 6 | 82 | `        "-..", ".", "..-.", "--.", "....", "..", ".---", "-.-", ".-..", "--", "-.", "---", ".--.", "--.-",` |
| 7 | 81 | `        ".-.", "...", "-", "..-", "...-", ".--", "-..-", "-.--", "--..", "-----", ".----", "..---", "...--",` |
| 8 | 41 | `        "....-", ".....", "-....", "--...", "---..", "----."};` |
| 9 | 30 | `    const char *message = "MEET ME AT PIER 9 AT 1745";` |
| 10 | 16 | `    char encoded[512] = "";` |
| 11 | 25 | `    for (int i = 0; message[i]; i++) {` |
| 12 | 19 | `        if (message[i] == ' ') {` |
| 13 | 16 | `            strcat(encoded, " / ");` |
| 14 | 6 | `            continue;` |
| 15 | 4 | `        }` |
| 16 | 25 | `        if (i && message[i - 1] != ' ')` |
| 17 | 14 | `            strcat(encoded, " ");` |
| 18 | 23 | `        const char *p = strchr(symbols, message[i]);` |
| 19 | 18 | `        strcat(encoded, codes[p - symbols]);` |
| 20 | 3 | `    }` |
| 22 | 11 | `    char decoded[128];` |
| 23 | 10 | `    int d = 0;` |
| 24 | 42 | `    for (char *token = strtok(encoded, " "); token; token = strtok(NULL, " ")) {` |
| 25 | 20 | `        if (strcmp(token, "/") == 0)` |
| 26 | 16 | `            decoded[d++] = ' ';` |
| 27 | 4 | `        else` |
| 28 | 27 | `            for (int i = 0; i < 36; i++)` |
| 29 | 25 | `                if (strcmp(token, codes[i]) == 0) {` |
| 30 | 19 | `                    decoded[d++] = symbols[i];` |
| 31 | 8 | `                    break;` |
| 32 | 6 | `                }` |
| 33 | 3 | `    }` |
| 34 | 11 | `    decoded[d] = 0;` |
| 35 | 7 | `    puts(decoded);` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **651 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 694 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 653 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
