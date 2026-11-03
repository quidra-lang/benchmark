# Task B selection: 89_dijkstra / Java

## Common answer requirements

Locate source-zero initialization and source-specific predecessor termination; explain G-rooted reconstruction, unchanged A–G output order and G self-path.

## Answer and source dependencies

Move the sole zero-distance seed from A to G: index6 in zero-based implementations and index7 in one-based implementations. Preserve the all-other-vertices infinite/unreached initializer; A must no longer receive the old zero seed. The selected character/index mapping establishes G. Keep the predecessor initializer and generic sentinel termination (negative, None, zero or nil) unchanged where present: following the G predecessor reaches that sentinel. In Dart and Zig the explicit root stop compares to0, so change that comparison to6 together with the seed; the default previous value is then not followed after reaching G. Preserve the existing path assembly, output label order and formatting, which do not require further edits.



## Scope and dependency evidence checked after independent review

The smaller candidate retains the all-vertex distance/predecessor initialization, sole zero seed, vertex-name/index mapping, and reconstruction termination/update site. These distinguish the source-specific0 test in Dart/Zig from generic predecessor-sentinel loops elsewhere. Unchanged finalized-state handling, edge relaxation and complete path-list/output formatting add no affected dependency and are removed. The existing mapping is retained only to establish G6 or G7, not to reproduce unchanged output construction.

Source: `Main.java`. Selected original locations: L16,L17,L18,L37,L38.

- L16: `        Arrays.fill(distance, Integer.MAX_VALUE);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        Arrays.fill(previous, -1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        distance[0] = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            for (int u = v; u >= 0; u = previous[u]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `                path.add(String.valueOf((char)('A' + u)));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **106 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 206 tokens. The contiguous original span L16–L38 costs 448 tokens; the complete original source costs 851 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L16: 89 tokens; removes `Arrays.fill(distance, Integer.MAX_VALUE);` from the dependency chain described above.
- Without L17: 92 tokens; removes `Arrays.fill(previous, -1);` from the dependency chain described above.
- Without L18: 94 tokens; removes `distance[0] = 0;` from the dependency chain described above.
- Without L37: 72 tokens; removes `for (int u = v; u >= 0; u = previous[u]) {` from the dependency chain described above.
- Without L38: 77 tokens; removes `path.add(String.valueOf((char)('A' + u)));` from the dependency chain described above.
