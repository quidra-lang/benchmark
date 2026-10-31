# Task B selection: 89_dijkstra / C++

## Common answer requirements

Locate source-zero initialization and source-specific predecessor termination; explain G-rooted reconstruction, unchanged A–G output order and G self-path.

## Answer and source dependencies

Move the sole zero-distance seed from A to G: index6 in zero-based implementations and index7 in one-based implementations. Preserve the all-other-vertices infinite/unreached initializer; A must no longer receive the old zero seed. The selected character/index mapping establishes G. Keep the predecessor initializer and generic sentinel termination (negative, None, zero or nil) unchanged where present: following the G predecessor reaches that sentinel. In Dart and Zig the explicit root stop compares to0, so change that comparison to6 together with the seed; the default previous value is then not followed after reaching G. Preserve the existing path assembly, output label order and formatting, which do not require further edits.



## Scope and dependency evidence checked after independent review

The predecessor loop uses a generic negative sentinel and needs no root-literal edit. Its original single-statement path append is retained so the following alphabet-mapping output line cannot be interpreted as the loop body. The initializer, sole distance seed and actual A-plus-vertex mapping identify the G index6 change; leave path assembly/output formatting otherwise unchanged.

Source: `main.cpp`. Selected original locations: L14,L15,L16,L31,L32,L34.

- L14: `    distance.fill(1000000);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    parent.fill(-1);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    distance[0] = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        for (int u = v; u >= 0; u = parent[u])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            path.push_back(u);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        std::cout << static_cast<char>('A' + v) << ": distance=" << distance[v] << " path=";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **129 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 116 tokens. The contiguous original span L14–L34 costs 426 tokens; the complete original source costs 813 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L14: 114 tokens; removes `distance.fill(1000000);` from the dependency chain described above.
- Without L15: 119 tokens; removes `parent.fill(-1);` from the dependency chain described above.
- Without L16: 118 tokens; removes `distance[0] = 0;` from the dependency chain described above.
- Without L31: 98 tokens; removes `for (int u = v; u >= 0; u = parent[u])` from the dependency chain described above.
- Without L32: 116 tokens; removes `path.push_back(u);` from the dependency chain described above.
- Without L34: 80 tokens; removes `std::cout << static_cast<char>('A' + v) << ": distance=" << distance[v] << " path=";` from the dependency chain described above.
