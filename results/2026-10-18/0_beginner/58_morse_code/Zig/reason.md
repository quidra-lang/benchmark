# Task B selection: 58_morse_code / Zig

## Common answer requirements

Identify the generated-Morse-to-message data path; trace the first ME / AT boundary, distinguishing letter and word separators; identify mapping and generated separator information supplying decoded letters/spaces and establish reconstruction without reading original-message characters.

## Supported analysis

At the ME-to-AT boundary the generated text is "-- . / .- -": spaces separate letter codes, while the slash marker (normally framed by spaces) separates words. Decoding resolves -- to M and . to E, then creates one decoded space from the word boundary, followed by .- to A and - to T. The table/alphabet or reverse map provides letters; the generated boundary supplies spaces. The decode path consumes encoded text, not characters from message. Nested word/letter split implementations split " / " first, split each word on spaces, concatenate letters, and join decoded words with spaces. Token-stream implementations split on spaces and handle the standalone slash token specially. The selected encoder separator operations establish where that distinction is generated.

The generated slice ends at len; splitScalar produces slash as a token, eql tests it, and matching codes index alphabet for letters. need_space resets after an encoded word delimiter. The selected writer construction and out alias identify std.Io.Writer as the implementation of the visible print/write operations; buffer allocation/flush behavior is unrelated to this question. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.zig`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 5 | 32 | `    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);` |
| 6 | 13 | `    const out = &writer.interface;` |
| 7 | 16 | `    const codes = [_][]const u8{` |
| 8 | 65 | `        ".-",    "-...",  "-.-.",  "-..",   ".",     "..-.",  "--.",   "....",  "..",    ".---",` |
| 9 | 64 | `        "-.-",   ".-..",  "--",    "-.",    "---",   ".--.",  "--.-",  ".-.",   "...",   "-",` |
| 10 | 67 | `        "..-",   "...-",  ".--",   "-..-",  "-.--",  "--..",  "-----", ".----", "..---", "...--",` |
| 11 | 40 | `        "....-", ".....", "-....", "--...", "---..", "----.",` |
| 12 | 4 | `    };` |
| 13 | 12 | `    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";` |
| 14 | 27 | `    const message = "MEET ME AT PIER 9 AT 1745";` |
| 15 | 18 | `    var encoded: [512]u8 = undefined;` |
| 16 | 13 | `    var len: usize = 0;` |
| 17 | 12 | `    var need_space = false;` |
| 18 | 13 | `    for (message) \|c\| {` |
| 19 | 16 | `        if (c == ' ') {` |
| 20 | 26 | `            @memcpy(encoded[len..][0..3], " / ");` |
| 21 | 10 | `            len += 3;` |
| 22 | 12 | `            need_space = false;` |
| 23 | 6 | `            continue;` |
| 24 | 4 | `        }` |
| 25 | 12 | `        if (need_space) {` |
| 26 | 15 | `            encoded[len] = ' ';` |
| 27 | 10 | `            len += 1;` |
| 28 | 4 | `        }` |
| 29 | 57 | `        const index: usize = if (c >= 'A' and c <= 'Z') c - 'A' else 26 + c - '0';` |
| 30 | 28 | `        @memcpy(encoded[len..][0..codes[index].len], codes[index]);` |
| 31 | 13 | `        len += codes[index].len;` |
| 32 | 11 | `        need_space = true;` |
| 33 | 3 | `    }` |
| 35 | 31 | `    var tokens = std.mem.splitScalar(u8, encoded[0..len], ' ');` |
| 36 | 17 | `    while (tokens.next()) \|token\| {` |
| 37 | 25 | `        if (std.mem.eql(u8, token, "/")) {` |
| 38 | 16 | `            try out.writeByte(' ');` |
| 39 | 8 | `        } else {` |
| 40 | 22 | `            for (codes, 0..) \|code, i\| {` |
| 41 | 25 | `                if (std.mem.eql(u8, code, token)) {` |
| 42 | 19 | `                    try out.writeByte(alphabet[i]);` |
| 43 | 8 | `                    break;` |
| 44 | 6 | `                }` |
| 45 | 5 | `            }` |
| 46 | 4 | `        }` |
| 47 | 3 | `    }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **812 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 925 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 814 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
