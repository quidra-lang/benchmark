# Task B selection: 89_dijkstra / Lua

## Common answer requirements

Locate source-zero initialization and source-specific predecessor termination; explain G-rooted reconstruction, unchanged A–G output order and G self-path.

## Answer and source dependencies

Move the sole zero-distance seed from A to G: index6 in zero-based implementations and index7 in one-based implementations. Preserve the all-other-vertices infinite/unreached initializer; A must no longer receive the old zero seed. The selected character/index mapping establishes G. Keep the predecessor initializer and generic sentinel termination (negative, None, zero or nil) unchanged where present: following the G predecessor reaches that sentinel. In Dart and Zig the explicit root stop compares to0, so change that comparison to6 together with the seed; the default previous value is then not followed after reaching G. Preserve the existing path assembly, output label order and formatting, which do not require further edits.



## Scope and dependency evidence checked after independent review

The smaller candidate retains the all-vertex distance/predecessor initialization, sole zero seed, vertex-name/index mapping, and reconstruction termination/update site. These distinguish the source-specific0 test in Dart/Zig from generic predecessor-sentinel loops elsewhere. Unchanged finalized-state handling, edge relaxation and complete path-list/output formatting add no affected dependency and are removed. The existing mapping is retained only to establish G6 or G7, not to reproduce unchanged output construction.

Source: `main.lua`. Selected original locations: L1,L12,L13,L14,L31,L32,L33.

- L1: `local names = "ABCDEFG"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `local distance, previous, finalized = {}, {}, {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `for i = 1, 7 do distance[i] = math.huge end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `distance[1] = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    while vertex do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        table.insert(path, 1, names:sub(vertex, vertex))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        vertex = previous[vertex]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **109 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 196 tokens. The contiguous original span L1–L33 costs 619 tokens; the complete original source costs 682 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 99 tokens; removes `local names = "ABCDEFG"` from the dependency chain described above.
- Without L12: 86 tokens; removes `local distance, previous, finalized = {}, {}, {}` from the dependency chain described above.
- Without L13: 83 tokens; removes `for i = 1, 7 do distance[i] = math.huge end` from the dependency chain described above.
- Without L14: 100 tokens; removes `distance[1] = 0` from the dependency chain described above.
- Without L31: 102 tokens; removes `while vertex do` from the dependency chain described above.
- Without L32: 86 tokens; removes `table.insert(path, 1, names:sub(vertex, vertex))` from the dependency chain described above.
- Without L33: 98 tokens; removes `vertex = previous[vertex]` from the dependency chain described above.
