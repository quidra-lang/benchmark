# Task B selection: 89_dijkstra / Kotlin

## Common answer requirements

Locate source-zero initialization and source-specific predecessor termination; explain G-rooted reconstruction, unchanged A–G output order and G self-path.

## Answer and source dependencies

Move the sole zero-distance seed from A to G: index6 in zero-based implementations and index7 in one-based implementations. Preserve the all-other-vertices infinite/unreached initializer; A must no longer receive the old zero seed. The selected character/index mapping establishes G. Keep the predecessor initializer and generic sentinel termination (negative, None, zero or nil) unchanged where present: following the G predecessor reaches that sentinel. In Dart and Zig the explicit root stop compares to0, so change that comparison to6 together with the seed; the default previous value is then not followed after reaching G. Preserve the existing path assembly, output label order and formatting, which do not require further edits.



## Scope and dependency evidence checked after independent review

The smaller candidate retains the all-vertex distance/predecessor initialization, sole zero seed, vertex-name/index mapping, and reconstruction termination/update site. These distinguish the source-specific0 test in Dart/Zig from generic predecessor-sentinel loops elsewhere. Unchanged finalized-state handling, edge relaxation and complete path-list/output formatting add no affected dependency and are removed. The existing mapping is retained only to establish G6 or G7, not to reproduce unchanged output construction.

Source: `main.kt`. Selected original locations: L11,L12,L13,L28,L29,L30.

- L11: `    val distance = IntArray(7) { Int.MAX_VALUE }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    val previous = IntArray(7) { -1 }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    distance[0] = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        while (u >= 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            path.add('A' + u)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            u = previous[u]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **95 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 160 tokens. The contiguous original span L11–L30 costs 324 tokens; the complete original source costs 613 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L11: 72 tokens; removes `val distance = IntArray(7) { Int.MAX_VALUE }` from the dependency chain described above.
- Without L12: 75 tokens; removes `val previous = IntArray(7) { -1 }` from the dependency chain described above.
- Without L13: 85 tokens; removes `distance[0] = 0` from the dependency chain described above.
- Without L28: 81 tokens; removes `while (u >= 0) {` from the dependency chain described above.
- Without L29: 79 tokens; removes `path.add('A' + u)` from the dependency chain described above.
- Without L30: 83 tokens; removes `u = previous[u]` from the dependency chain described above.
