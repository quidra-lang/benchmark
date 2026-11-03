# Task B selection: 58_morse_code / Dart

## Common answer requirements

Identify the generated-Morse-to-message data path; trace the first ME / AT boundary, distinguishing letter and word separators; identify mapping and generated separator information supplying decoded letters/spaces and establish reconstruction without reading original-message characters.

## Supported analysis

At the ME-to-AT boundary the generated text is "-- . / .- -": spaces separate letter codes, while the slash marker (normally framed by spaces) separates words. Decoding resolves -- to M and . to E, then creates one decoded space from the word boundary, followed by .- to A and - to T. The table/alphabet or reverse map provides letters; the generated boundary supplies spaces. The decode path consumes encoded text, not characters from message. Nested word/letter split implementations split " / " first, split each word on spaces, concatenate letters, and join decoded words with spaces. Token-stream implementations split on spaces and handle the standalone slash token specially. The selected encoder separator operations establish where that distinction is generated.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.dart`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 2 | 9 | `  const codes = [` |
| 3 | 6 | `    '.-',` |
| 4 | 7 | `    '-...',` |
| 5 | 7 | `    '-.-.',` |
| 6 | 7 | `    '-..',` |
| 7 | 6 | `    '.',` |
| 8 | 7 | `    '..-.',` |
| 9 | 7 | `    '--.',` |
| 10 | 7 | `    '....',` |
| 11 | 6 | `    '..',` |
| 12 | 7 | `    '.---',` |
| 13 | 7 | `    '-.-',` |
| 14 | 7 | `    '.-..',` |
| 15 | 6 | `    '--',` |
| 16 | 6 | `    '-.',` |
| 17 | 7 | `    '---',` |
| 18 | 7 | `    '.--.',` |
| 19 | 7 | `    '--.-',` |
| 20 | 7 | `    '.-.',` |
| 21 | 6 | `    '...',` |
| 22 | 6 | `    '-',` |
| 23 | 7 | `    '..-',` |
| 24 | 7 | `    '...-',` |
| 25 | 7 | `    '.--',` |
| 26 | 7 | `    '-..-',` |
| 27 | 7 | `    '-.--',` |
| 28 | 7 | `    '--..',` |
| 29 | 8 | `    '-----',` |
| 30 | 8 | `    '.----',` |
| 31 | 8 | `    '..---',` |
| 32 | 7 | `    '...--',` |
| 33 | 7 | `    '....-',` |
| 34 | 7 | `    '.....',` |
| 35 | 7 | `    '-....',` |
| 36 | 7 | `    '--...',` |
| 37 | 8 | `    '---..',` |
| 38 | 8 | `    '----.',` |
| 39 | 4 | `  ];` |
| 40 | 12 | `  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';` |
| 41 | 27 | `  const message = 'MEET ME AT PIER 9 AT 1745';` |
| 42 | 9 | `  final encoded = message` |
| 43 | 10 | `      .split(' ')` |
| 44 | 47 | `      .map((w) => w.split('').map((c) => codes[alphabet.indexOf(c)]).join(' '))` |
| 45 | 13 | `      .join(' / ');` |
| 46 | 9 | `  final decoded = encoded` |
| 47 | 12 | `      .split(' / ')` |
| 48 | 45 | `      .map((w) => w.split(' ').map((c) => alphabet[codes.indexOf(c)]).join())` |
| 49 | 11 | `      .join(' ');` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **458 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 482 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 460 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
