# Task B selection: 89_dijkstra / PHP

## Common answer requirements

Locate source-zero initialization and source-specific predecessor termination; explain G-rooted reconstruction, unchanged A–G output order and G self-path.

## Answer and source dependencies

Move the sole zero-distance seed from A to G: index6 in zero-based implementations and index7 in one-based implementations. Preserve the all-other-vertices infinite/unreached initializer; A must no longer receive the old zero seed. The selected character/index mapping establishes G. Keep the predecessor initializer and generic sentinel termination (negative, None, zero or nil) unchanged where present: following the G predecessor reaches that sentinel. In Dart and Zig the explicit root stop compares to0, so change that comparison to6 together with the seed; the default previous value is then not followed after reaching G. Preserve the existing path assembly, output label order and formatting, which do not require further edits.



## Scope and dependency evidence checked after independent review

The smaller candidate retains the all-vertex distance/predecessor initialization, sole zero seed, vertex-name/index mapping, and reconstruction termination/update site. These distinguish the source-specific0 test in Dart/Zig from generic predecessor-sentinel loops elsewhere. Unchanged finalized-state handling, edge relaxation and complete path-list/output formatting add no affected dependency and are removed. The existing mapping is retained only to establish G6 or G7, not to reproduce unchanged output construction.

Source: `main.php`. Selected original locations: L3,L14,L15,L16,L37,L38,L39.

- L3: `$names = str_split('ABCDEFG');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `$distance = array_fill(0, 7, PHP_INT_MAX);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `$distance[0] = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `$previous = array_fill(0, 7, -1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    while ($vertex >= 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        array_unshift($path, $names[$vertex]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `        $vertex = $previous[$vertex];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **117 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 182 tokens. The contiguous original span L3–L39 costs 748 tokens; the complete original source costs 804 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 102 tokens; removes `$names = str_split('ABCDEFG');` from the dependency chain described above.
- Without L14: 94 tokens; removes `$distance = array_fill(0, 7, PHP_INT_MAX);` from the dependency chain described above.
- Without L15: 106 tokens; removes `$distance[0] = 0;` from the dependency chain described above.
- Without L16: 97 tokens; removes `$previous = array_fill(0, 7, -1);` from the dependency chain described above.
- Without L37: 103 tokens; removes `while ($vertex >= 0) {` from the dependency chain described above.
- Without L38: 98 tokens; removes `array_unshift($path, $names[$vertex]);` from the dependency chain described above.
- Without L39: 102 tokens; removes `$vertex = $previous[$vertex];` from the dependency chain described above.
