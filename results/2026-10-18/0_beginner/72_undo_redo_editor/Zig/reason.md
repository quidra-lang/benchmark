# Task B selection: 72_undo_redo_editor / Zig

## Common answer requirements

Trace undoable and redoable histories from type there through the redo after type friend; establish the prior buffer/history, exact spaces in restored contents, stack transfer semantics, and future invalidation on a new edit.

## Supported analysis

Initially the empty undo is a no-op. Typing hello world stores the empty snapshot; deleting five letters leaves "hello " with its trailing space and preserves "hello world" as the prior snapshot. At "type there", buffer becomes "hello there", undo snapshots bottom-to-top are ["", "hello world", "hello "], and redo is empty. First undo restores "hello " and makes "hello there" redoable. Second undo restores "hello world"; redo bottom-to-top becomes ["hello there", "hello "], so the deletion back to "hello " is the next redo, followed by typing there. The redo restores "hello " and leaves "hello there" redoable. Typing friend appends to that retained trailing space, producing "hello friend"; it pushes "hello " to undo and clears redo, abandoning "hello there". The following redo has nothing to redo and leaves "hello friend" unchanged. Source push/pop/copy and clear/reset operations establish these exact snapshots rather than treating history as abstract commands.

Snapshot contains the fixed text array by value and a logical len. Assignments copy both; resetting rlen=0 invalidates old redo states without needing to erase storage. delete reduces len, so the trailing space left after deleting world is retained. The selected writer construction and out alias identify std.Io.Writer as the implementation of the visible print/write operations; buffer allocation/flush behavior is unrelated to this question. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.zig`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 3 | 37 | `const Snapshot = struct { text: [128]u8 = undefined, len: usize = 0 };` |
| 7 | 32 | `    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);` |
| 8 | 13 | `    const out = &writer.interface;` |
| 9 | 16 | `    const commands = [_][]const u8{` |
| 10 | 7 | `        "undo",` |
| 11 | 11 | `        "type hello world",` |
| 12 | 9 | `        "delete 5",` |
| 13 | 9 | `        "type there",` |
| 14 | 7 | `        "undo",` |
| 15 | 7 | `        "undo",` |
| 16 | 7 | `        "redo",` |
| 17 | 9 | `        "type friend",` |
| 18 | 7 | `        "redo",` |
| 24 | 4 | `    };` |
| 25 | 12 | `    var current = Snapshot{};` |
| 26 | 17 | `    var undo: [14]Snapshot = undefined;` |
| 27 | 17 | `    var redo: [14]Snapshot = undefined;` |
| 28 | 13 | `    var ulen: usize = 0;` |
| 29 | 13 | `    var rlen: usize = 0;` |
| 30 | 13 | `    for (commands) \|command\| {` |
| 32 | 25 | `        if (std.mem.eql(u8, command, "undo")) {` |
| 33 | 15 | `            if (ulen == 0) {` |
| 34 | 23 | `                try out.writeAll("nothing to undo\n");` |
| 35 | 7 | `                continue;` |
| 36 | 5 | `            }` |
| 37 | 13 | `            redo[rlen] = current;` |
| 38 | 10 | `            rlen += 1;` |
| 39 | 10 | `            ulen -= 1;` |
| 40 | 13 | `            current = undo[ulen];` |
| 41 | 29 | `        } else if (std.mem.eql(u8, command, "redo")) {` |
| 42 | 15 | `            if (rlen == 0) {` |
| 43 | 23 | `                try out.writeAll("nothing to redo\n");` |
| 44 | 7 | `                continue;` |
| 45 | 5 | `            }` |
| 46 | 13 | `            undo[ulen] = current;` |
| 47 | 10 | `            ulen += 1;` |
| 48 | 10 | `            rlen -= 1;` |
| 49 | 13 | `            current = redo[rlen];` |
| 50 | 8 | `        } else {` |
| 51 | 13 | `            undo[ulen] = current;` |
| 52 | 10 | `            ulen += 1;` |
| 53 | 10 | `            rlen = 0;` |
| 54 | 28 | `            if (std.mem.startsWith(u8, command, "type ")) {` |
| 55 | 17 | `                const text = command[5..];` |
| 56 | 29 | `                @memcpy(current.text[current.len..][0..text.len], text);` |
| 57 | 15 | `                current.len += text.len;` |
| 58 | 9 | `            } else {` |
| 59 | 34 | `                const n = try std.fmt.parseInt(usize, command[7..], 10);` |
| 60 | 22 | `                current.len -= @min(current.len, n);` |
| 61 | 5 | `            }` |
| 62 | 4 | `        }` |
| 64 | 3 | `    }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **713 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 888 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 715 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
