# Task B selection: 72_undo_redo_editor / C

## Common answer requirements

Trace undoable and redoable histories from type there through the redo after type friend; establish the prior buffer/history, exact spaces in restored contents, stack transfer semantics, and future invalidation on a new edit.

## Supported analysis

Initially the empty undo is a no-op. Typing hello world stores the empty snapshot; deleting five letters leaves "hello " with its trailing space and preserves "hello world" as the prior snapshot. At "type there", buffer becomes "hello there", undo snapshots bottom-to-top are ["", "hello world", "hello "], and redo is empty. First undo restores "hello " and makes "hello there" redoable. Second undo restores "hello world"; redo bottom-to-top becomes ["hello there", "hello "], so the deletion back to "hello " is the next redo, followed by typing there. The redo restores "hello " and leaves "hello there" redoable. Typing friend appends to that retained trailing space, producing "hello friend"; it pushes "hello " to undo and clears redo, abandoning "hello there". The following redo has nothing to redo and leaves "hello friend" unchanged. Source push/pop/copy and clear/reset operations establish these exact snapshots rather than treating history as abstract commands.

The u/r indices are logical stack lengths; resetting r to zero invalidates every old redo entry even though bytes may remain in the array. strcpy stores independent text snapshots. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.c`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 6 | 50 | `    const char *commands[] = {"undo", "type hello world", "delete 5", "type there", "undo", "undo",` |
| 7 | 52 | `        "redo", "type friend", "redo", "delete 20", "undo", "redo", "redo", "type see you"};` |
| 8 | 40 | `    char buffer[256] = "", undo[32][256], redo[32][256];` |
| 9 | 17 | `    int u = 0, r = 0;` |
| 10 | 27 | `    for (int i = 0; i < 14; i++) {` |
| 11 | 17 | `        const char *command = commands[i];` |
| 12 | 22 | `        if (strcmp(command, "undo") == 0) {` |
| 13 | 12 | `            if (!u) {` |
| 14 | 20 | `                puts("undo => nothing to undo");` |
| 15 | 7 | `                continue;` |
| 16 | 5 | `            }` |
| 17 | 16 | `            strcpy(redo[r++], buffer);` |
| 18 | 16 | `            strcpy(buffer, undo[--u]);` |
| 19 | 26 | `        } else if (strcmp(command, "redo") == 0) {` |
| 20 | 12 | `            if (!r) {` |
| 21 | 20 | `                puts("redo => nothing to redo");` |
| 22 | 7 | `                continue;` |
| 23 | 5 | `            }` |
| 24 | 16 | `            strcpy(undo[u++], buffer);` |
| 25 | 16 | `            strcpy(buffer, redo[--r]);` |
| 26 | 8 | `        } else {` |
| 27 | 16 | `            strcpy(undo[u++], buffer);` |
| 28 | 10 | `            r = 0;` |
| 29 | 27 | `            if (strncmp(command, "type ", 5) == 0) {` |
| 30 | 17 | `                strcat(buffer, command + 5);` |
| 31 | 9 | `            } else {` |
| 32 | 33 | `                int count = atoi(command + 7), len = (int)strlen(buffer);` |
| 33 | 30 | `                buffer[count > len ? 0 : len - count] = 0;` |
| 34 | 5 | `            }` |
| 35 | 4 | `        }` |
| 37 | 3 | `    }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **565 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 638 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 567 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
