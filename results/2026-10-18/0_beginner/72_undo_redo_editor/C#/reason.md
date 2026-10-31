# Task B selection: 72_undo_redo_editor / C#

## Common answer requirements

Trace undoable and redoable histories from type there through the redo after type friend; establish the prior buffer/history, exact spaces in restored contents, stack transfer semantics, and future invalidation on a new edit.

## Supported analysis

Initially the empty undo is a no-op. Typing hello world stores the empty snapshot; deleting five letters leaves "hello " with its trailing space and preserves "hello world" as the prior snapshot. At "type there", buffer becomes "hello there", undo snapshots bottom-to-top are ["", "hello world", "hello "], and redo is empty. First undo restores "hello " and makes "hello there" redoable. Second undo restores "hello world"; redo bottom-to-top becomes ["hello there", "hello "], so the deletion back to "hello " is the next redo, followed by typing there. The redo restores "hello " and leaves "hello there" redoable. Typing friend appends to that retained trailing space, producing "hello friend"; it pushes "hello " to undo and clears redo, abandoning "hello there". The following redo has nothing to redo and leaves "hello friend" unchanged. Source push/pop/copy and clear/reset operations establish these exact snapshots rather than treating history as abstract commands.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `Program.cs`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 7 | 52 | `string[] commands = { "undo", "type hello world", "delete 5", "type there", "undo", "undo", "redo",` |
| 8 | 47 | `    "type friend", "redo", "delete 20", "undo", "redo", "redo", "type see you" };` |
| 9 | 16 | `var undo = new Stack<string>();` |
| 10 | 16 | `var redo = new Stack<string>();` |
| 11 | 10 | `string buffer = "";` |
| 12 | 12 | `foreach (string command in commands)` |
| 13 | 2 | `{` |
| 15 | 13 | `    if (command == "undo")` |
| 16 | 3 | `    {` |
| 17 | 14 | `        if (undo.Count == 0)` |
| 18 | 4 | `        {` |
| 19 | 16 | `            special = "nothing to undo";` |
| 20 | 4 | `        }` |
| 21 | 4 | `        else` |
| 22 | 4 | `        {` |
| 23 | 11 | `            redo.Push(buffer);` |
| 24 | 14 | `            buffer = undo.Pop();` |
| 25 | 4 | `        }` |
| 26 | 3 | `    }` |
| 27 | 15 | `    else if (command == "redo")` |
| 28 | 3 | `    {` |
| 29 | 14 | `        if (redo.Count == 0)` |
| 30 | 4 | `        {` |
| 31 | 16 | `            special = "nothing to redo";` |
| 32 | 4 | `        }` |
| 33 | 4 | `        else` |
| 34 | 4 | `        {` |
| 35 | 11 | `            undo.Push(buffer);` |
| 36 | 14 | `            buffer = redo.Pop();` |
| 37 | 4 | `        }` |
| 38 | 3 | `    }` |
| 39 | 3 | `    else` |
| 40 | 3 | `    {` |
| 41 | 10 | `        undo.Push(buffer);` |
| 42 | 9 | `        redo.Clear();` |
| 43 | 23 | `        if (command.StartsWith("type ", StringComparison.Ordinal))` |
| 44 | 14 | `            buffer += command[5..];` |
| 45 | 4 | `        else` |
| 46 | 44 | `            buffer = buffer[..Math.Max(0, buffer.Length - int.Parse(command[7..], CultureInfo.InvariantCulture))];` |
| 47 | 3 | `    }` |
| 49 | 2 | `}` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **460 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 551 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 460 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
