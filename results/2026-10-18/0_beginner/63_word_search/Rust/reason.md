# Task B selection: 63_word_search / Rust

## Common answer requirements

Identify all first-match exits and output/result state; explain preserving row-major cells and E,SE,S,SW,W,NW,N,NE direction order, visiting all valid matches, retaining the final match or not-found fallback in the current per-word format.

## Supported analysis

Keep the shown increasing row/column/direction traversal. Replace first-success return/break with overwriting a saved result for each successful match; finish all search loops before returning or printing it. Remove found-based loop guards and all success exits that suppress later combinations. Keep the character-mismatch break inside the match test, because it rejects only the current candidate. Initialize the saved result to the existing not-found value, or retain a separate any-match flag and saved coordinates/direction. For implementations that print directly on success, move that print after the loops and print only the last saved tuple, falling back to not found when none was saved. The actual grid and word fixtures and unchanged match predicate internals are not needed to identify these edits.

Return type Option allows a mutable last-match Option initialized to None, overwritten with Some for each match and returned after traversal. The existing caller formats Some/None unchanged. The all(...) opening conditional is retained with its closing call delimiter so the success branch is tied to the existing complete-match gate; predicate internals remain unchanged. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.rs`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 38 | `fn search(board: &[&str], word: &str) -> Option<(i32, i32, usize)> {` |
| 2 | 9 | `    let directions = [` |
| 3 | 10 | `        (0, 1),` |
| 4 | 10 | `        (1, 1),` |
| 5 | 10 | `        (1, 0),` |
| 6 | 11 | `        (1, -1),` |
| 7 | 11 | `        (0, -1),` |
| 8 | 12 | `        (-1, -1),` |
| 9 | 11 | `        (-1, 0),` |
| 10 | 11 | `        (-1, 1),` |
| 11 | 4 | `    ];` |
| 12 | 18 | `    for r in 0..10_i32 {` |
| 13 | 19 | `        for c in 0..10_i32 {` |
| 14 | 31 | `            for (d, (dr, dc)) in directions.iter().enumerate() {` |
| 15 | 29 | `                if word.bytes().enumerate().all(\|(k, ch)\| {` |
| 21 | 9 | `                }) {` |
| 22 | 21 | `                    return Some((r, c, d));` |
| 23 | 6 | `                }` |
| 24 | 5 | `            }` |
| 25 | 4 | `        }` |
| 26 | 3 | `    }` |
| 27 | 3 | `    None` |
| 28 | 2 | `}` |
| 43 | 49 | `    let names = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"];` |
| 45 | 32 | `        if let Some((r, c, d)) = search(&board, word) {` |
| 46 | 40 | `            println!("{}: ({}, {}) {}", word, r, c, names[d]);` |
| 47 | 8 | `        } else {` |
| 48 | 20 | `            println!("{}: not found", word);` |
| 49 | 4 | `        }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **440 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 701 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 449 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
