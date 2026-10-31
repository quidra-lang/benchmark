# Task B selection: 72_undo_redo_editor / C++

## Common answer requirements

Trace undoable and redoable histories from type there through the redo after type friend; establish the prior buffer/history, exact spaces in restored contents, stack transfer semantics, and future invalidation on a new edit.

## Supported analysis

Initially the empty undo is a no-op. Typing hello world stores the empty snapshot; deleting five letters leaves "hello " with its trailing space and preserves "hello world" as the prior snapshot. At "type there", buffer becomes "hello there", undo snapshots bottom-to-top are ["", "hello world", "hello "], and redo is empty. First undo restores "hello " and makes "hello there" redoable. Second undo restores "hello world"; redo bottom-to-top becomes ["hello there", "hello "], so the deletion back to "hello " is the next redo, followed by typing there. The redo restores "hello " and leaves "hello there" redoable. Typing friend appends to that retained trailing space, producing "hello friend"; it pushes "hello " to undo and clears redo, abandoning "hello there". The following redo has nothing to redo and leaves "hello friend" unchanged. Source push/pop/copy and clear/reset operations establish these exact snapshots rather than treating history as abstract commands.

push_back copies string values; clear removes all redo snapshots. back plus pop_back implements the top-of-stack transfer. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.cpp`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 7 | 47 | `    std::array<std::string, 14> commands = {"undo", "type hello world", "delete 5", "type there",` |
| 8 | 62 | `        "undo", "undo", "redo", "type friend", "redo", "delete 20", "undo", "redo", "redo", "type see you"};` |
| 9 | 8 | `    std::string buffer;` |
| 10 | 16 | `    std::vector<std::string> undo, redo;` |
| 11 | 20 | `    for (const std::string &command : commands) {` |
| 12 | 16 | `        if (command == "undo") {` |
| 13 | 15 | `            if (undo.empty()) {` |
| 14 | 25 | `                std::cout << "undo => nothing to undo\n";` |
| 15 | 7 | `                continue;` |
| 16 | 5 | `            }` |
| 17 | 13 | `            redo.push_back(buffer);` |
| 18 | 14 | `            buffer = undo.back();` |
| 19 | 12 | `            undo.pop_back();` |
| 20 | 20 | `        } else if (command == "redo") {` |
| 21 | 15 | `            if (redo.empty()) {` |
| 22 | 25 | `                std::cout << "redo => nothing to redo\n";` |
| 23 | 7 | `                continue;` |
| 24 | 5 | `            }` |
| 25 | 13 | `            undo.push_back(buffer);` |
| 26 | 14 | `            buffer = redo.back();` |
| 27 | 12 | `            redo.pop_back();` |
| 28 | 8 | `        } else {` |
| 29 | 13 | `            undo.push_back(buffer);` |
| 30 | 10 | `            redo.clear();` |
| 31 | 29 | `            if (command.compare(0, 5, "type ") == 0) {` |
| 32 | 16 | `                buffer += command.substr(5);` |
| 33 | 9 | `            } else {` |
| 34 | 39 | `                std::size_t count = static_cast<std::size_t>(std::stoi(command.substr(7)));` |
| 35 | 36 | `                buffer.resize(count > buffer.size() ? 0 : buffer.size() - count);` |
| 36 | 5 | `            }` |
| 37 | 4 | `        }` |
| 39 | 3 | `    }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **543 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 616 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 545 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
