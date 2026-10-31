# Task B selection: 89_dijkstra / C

## Common answer requirements

Locate source-zero initialization and source-specific predecessor termination; explain G-rooted reconstruction, unchanged A–G output order and G self-path.

## Answer and source dependencies

Move the sole zero-distance seed from A to G: index6 in zero-based implementations and index7 in one-based implementations. Preserve the all-other-vertices infinite/unreached initializer; A must no longer receive the old zero seed. The selected character/index mapping establishes G. Keep the predecessor initializer and generic sentinel termination (negative, None, zero or nil) unchanged where present: following the G predecessor reaches that sentinel. In Dart and Zig the explicit root stop compares to0, so change that comparison to6 together with the seed; the default previous value is then not followed after reaching G. Preserve the existing path assembly, output label order and formatting, which do not require further edits.



## Scope and dependency evidence checked after independent review

The predecessor loop uses a generic negative sentinel and needs no root-literal edit. Its original single-statement path append is retained so the following alphabet-mapping output line cannot be interpreted as the loop body. The initializer, sole distance seed and actual A-plus-vertex mapping identify the G index6 change; leave path assembly/output formatting otherwise unchanged.

Source: `main.c`. Selected original locations: L10,L11,L12,L13,L14,L29,L30,L31.

- L10: `    for (int i = 0; i < 7; i++) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        distance[i] = 1000000;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        parent[i] = -1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `    distance[0] = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        for (int u = v; u >= 0; u = parent[u])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            path[length++] = u;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        printf("%c: distance=%d path=", 'A' + v, distance[v]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **151 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 137 tokens. The contiguous original span L10–L31 costs 432 tokens; the complete original source costs 807 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L10: 125 tokens; removes `for (int i = 0; i < 7; i++) {` from the dependency chain described above.
- Without L11: 133 tokens; removes `distance[i] = 1000000;` from the dependency chain described above.
- Without L12: 138 tokens; removes `parent[i] = -1;` from the dependency chain described above.
- Without L13: 148 tokens; removes `}` from the dependency chain described above.
- Without L14: 140 tokens; removes `distance[0] = 0;` from the dependency chain described above.
- Without L29: 120 tokens; removes `for (int u = v; u >= 0; u = parent[u])` from the dependency chain described above.
- Without L30: 137 tokens; removes `path[length++] = u;` from the dependency chain described above.
- Without L31: 116 tokens; removes `printf("%c: distance=%d path=", 'A' + v, distance[v]);` from the dependency chain described above.
