# Task B selection: 72_undo_redo_editor / Lua

## Common answer requirements

Trace undoable and redoable histories from type there through the redo after type friend; establish the prior buffer/history, exact spaces in restored contents, stack transfer semantics, and future invalidation on a new edit.

## Supported analysis

Initially the empty undo is a no-op. Typing hello world stores the empty snapshot; deleting five letters leaves "hello " with its trailing space and preserves "hello world" as the prior snapshot. At "type there", buffer becomes "hello there", undo snapshots bottom-to-top are ["", "hello world", "hello "], and redo is empty. First undo restores "hello " and makes "hello there" redoable. Second undo restores "hello world"; redo bottom-to-top becomes ["hello there", "hello "], so the deletion back to "hello " is the next redo, followed by typing there. The redo restores "hello " and leaves "hello there" redoable. Typing friend appends to that retained trailing space, producing "hello friend"; it pushes "hello " to undo and clears redo, abandoning "hello there". The following redo has nothing to redo and leaves "hello friend" unchanged. Source push/pop/copy and clear/reset operations establish these exact snapshots rather than treating history as abstract commands.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.lua`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 8 | `local commands = {` |
| 2 | 51 | `    "undo", "type hello world", "delete 5", "type there", "undo", "undo", "redo", "type friend",` |
| 3 | 38 | `    "redo", "delete 20", "undo", "redo", "redo", "type see you",` |
| 5 | 27 | `local buffer, undo_stack, redo_stack = "", {}, {}` |
| 6 | 16 | `for _, command in ipairs(commands) do` |
| 7 | 5 | `    local result` |
| 8 | 13 | `    if command == "undo" then` |
| 9 | 15 | `        if #undo_stack == 0 then` |
| 10 | 15 | `            result = "nothing to undo"` |
| 11 | 4 | `        else` |
| 12 | 21 | `            redo_stack[#redo_stack + 1] = buffer` |
| 13 | 16 | `            buffer = table.remove(undo_stack)` |
| 14 | 4 | `        end` |
| 15 | 13 | `    elseif command == "redo" then` |
| 16 | 15 | `        if #redo_stack == 0 then` |
| 17 | 15 | `            result = "nothing to redo"` |
| 18 | 4 | `        else` |
| 19 | 21 | `            undo_stack[#undo_stack + 1] = buffer` |
| 20 | 16 | `            buffer = table.remove(redo_stack)` |
| 21 | 4 | `        end` |
| 22 | 3 | `    else` |
| 23 | 20 | `        undo_stack[#undo_stack + 1] = buffer` |
| 24 | 11 | `        redo_stack = {}` |
| 25 | 23 | `        if command:sub(1, 5) == "type " then` |
| 26 | 18 | `            buffer = buffer .. command:sub(6)` |
| 27 | 4 | `        else` |
| 28 | 38 | `            buffer = buffer:sub(1, math.max(0, #buffer - tonumber(command:sub(8))))` |
| 29 | 4 | `        end` |
| 30 | 3 | `    end` |
| 32 | 2 | `end` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **447 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 491 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 449 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
