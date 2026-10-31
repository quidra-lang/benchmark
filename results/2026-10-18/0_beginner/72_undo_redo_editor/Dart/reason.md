# Task B selection: 72_undo_redo_editor / Dart

## Common answer requirements

Trace undoable and redoable histories from type there through the redo after type friend; establish the prior buffer/history, exact spaces in restored contents, stack transfer semantics, and future invalidation on a new edit.

## Supported analysis

Initially the empty undo is a no-op. Typing hello world stores the empty snapshot; deleting five letters leaves "hello " with its trailing space and preserves "hello world" as the prior snapshot. At "type there", buffer becomes "hello there", undo snapshots bottom-to-top are ["", "hello world", "hello "], and redo is empty. First undo restores "hello " and makes "hello there" redoable. Second undo restores "hello world"; redo bottom-to-top becomes ["hello there", "hello "], so the deletion back to "hello " is the next redo, followed by typing there. The redo restores "hello " and leaves "hello there" redoable. Typing friend appends to that retained trailing space, producing "hello friend"; it pushes "hello " to undo and clears redo, abandoning "hello there". The following redo has nothing to redo and leaves "hello friend" unchanged. Source push/pop/copy and clear/reset operations establish these exact snapshots rather than treating history as abstract commands.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.dart`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 6 | 9 | `  const commands = [` |
| 7 | 6 | `    'undo',` |
| 8 | 10 | `    'type hello world',` |
| 9 | 8 | `    'delete 5',` |
| 10 | 8 | `    'type there',` |
| 11 | 6 | `    'undo',` |
| 12 | 6 | `    'undo',` |
| 13 | 6 | `    'redo',` |
| 14 | 8 | `    'type friend',` |
| 15 | 6 | `    'redo',` |
| 21 | 4 | `  ];` |
| 22 | 11 | `  var current = '';` |
| 23 | 23 | `  final undo = <String>[], redo = <String>[];` |
| 24 | 15 | `  for (final command in commands) {` |
| 26 | 15 | `    if (command == 'undo') {` |
| 27 | 13 | `      if (undo.isEmpty) {` |
| 28 | 16 | `        out.writeln('nothing to undo');` |
| 29 | 5 | `        continue;` |
| 30 | 4 | `      }` |
| 31 | 10 | `      redo.add(current);` |
| 32 | 14 | `      current = undo.removeLast();` |
| 33 | 19 | `    } else if (command == 'redo') {` |
| 34 | 13 | `      if (redo.isEmpty) {` |
| 35 | 16 | `        out.writeln('nothing to redo');` |
| 36 | 5 | `        continue;` |
| 37 | 4 | `      }` |
| 38 | 10 | `      undo.add(current);` |
| 39 | 14 | `      current = redo.removeLast();` |
| 40 | 7 | `    } else {` |
| 41 | 10 | `      undo.add(current);` |
| 42 | 9 | `      redo.clear();` |
| 43 | 19 | `      if (command.startsWith('type ')) {` |
| 44 | 14 | `        current += command.substring(5);` |
| 45 | 8 | `      } else {` |
| 46 | 21 | `        final n = int.parse(command.substring(7));` |
| 47 | 31 | `        current = current.substring(0, math.max(0, current.length - n));` |
| 48 | 4 | `      }` |
| 49 | 3 | `    }` |
| 51 | 3 | `  }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **413 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 534 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 415 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
