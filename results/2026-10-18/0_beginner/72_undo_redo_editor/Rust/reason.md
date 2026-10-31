# Task B selection: 72_undo_redo_editor / Rust

## Common answer requirements

Trace undoable and redoable histories from type there through the redo after type friend; establish the prior buffer/history, exact spaces in restored contents, stack transfer semantics, and future invalidation on a new edit.

## Supported analysis

Initially the empty undo is a no-op. Typing hello world stores the empty snapshot; deleting five letters leaves "hello " with its trailing space and preserves "hello world" as the prior snapshot. At "type there", buffer becomes "hello there", undo snapshots bottom-to-top are ["", "hello world", "hello "], and redo is empty. First undo restores "hello " and makes "hello there" redoable. Second undo restores "hello world"; redo bottom-to-top becomes ["hello there", "hello "], so the deletion back to "hello " is the next redo, followed by typing there. The redo restores "hello " and leaves "hello there" redoable. Typing friend appends to that retained trailing space, producing "hello friend"; it pushes "hello " to undo and clears redo, abandoning "hello there". The following redo has nothing to redo and leaves "hello friend" unchanged. Source push/pop/copy and clear/reset operations establish these exact snapshots rather than treating history as abstract commands.

Undo/redo transfer owned String values; editing stores buffer.clone(), so the old content remains a separate snapshot. redo.clear() abandons the old future. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.rs`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 2 | 9 | `    let commands = [` |
| 3 | 7 | `        "undo",` |
| 4 | 11 | `        "type hello world",` |
| 5 | 9 | `        "delete 5",` |
| 6 | 9 | `        "type there",` |
| 7 | 7 | `        "undo",` |
| 8 | 7 | `        "undo",` |
| 9 | 7 | `        "redo",` |
| 10 | 9 | `        "type friend",` |
| 11 | 7 | `        "redo",` |
| 17 | 4 | `    ];` |
| 18 | 16 | `    let mut buffer = String::new();` |
| 19 | 16 | `    let mut undo = Vec::new();` |
| 20 | 16 | `    let mut redo = Vec::new();` |
| 21 | 11 | `    for command in commands {` |
| 22 | 14 | `        if command == "undo" {` |
| 23 | 22 | `            if let Some(previous) = undo.pop() {` |
| 24 | 12 | `                redo.push(buffer);` |
| 25 | 11 | `                buffer = previous;` |
| 26 | 9 | `            } else {` |
| 27 | 21 | `                println!("undo => nothing to undo");` |
| 28 | 7 | `                continue;` |
| 29 | 5 | `            }` |
| 30 | 18 | `        } else if command == "redo" {` |
| 31 | 22 | `            if let Some(next) = redo.pop() {` |
| 32 | 12 | `                undo.push(buffer);` |
| 33 | 11 | `                buffer = next;` |
| 34 | 9 | `            } else {` |
| 35 | 21 | `                println!("redo => nothing to redo");` |
| 36 | 7 | `                continue;` |
| 37 | 5 | `            }` |
| 38 | 8 | `        } else {` |
| 39 | 15 | `            undo.push(buffer.clone());` |
| 40 | 10 | `            redo.clear();` |
| 41 | 28 | `            if let Some(text) = command.strip_prefix("type ") {` |
| 42 | 14 | `                buffer.push_str(text);` |
| 43 | 9 | `            } else {` |
| 44 | 27 | `                let count: usize = command[7..].parse().unwrap();` |
| 45 | 23 | `                buffer.truncate(buffer.len().saturating_sub(count));` |
| 46 | 5 | `            }` |
| 47 | 4 | `        }` |
| 49 | 3 | `    }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **497 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 576 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 499 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
