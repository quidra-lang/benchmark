# Task B selection: 71_knapsack_01 / Dart

## Common answer requirements

Locate capacity/table bounds and reconstruction/output dependencies; explain capacity 15 plus maximum-value, minimum-total-weight, lexicographically smallest increasing original-position sequence tie resolution with proper prefix first, reconstructing from DP and keeping printed names in original order.

## Supported analysis

Replace capacity 20 with 15 at the capacity initialization, loops, final-table lookup and any literal weight calculation; a compact table now has capacities 0..15 (16 columns). The present numeric maximum and inequality-only backtracking do not encode all requested ties. Use DP records containing value, total weight, increasing original item-position sequence, and the corresponding take/skip reconstruction choice; compare records by larger value, then smaller weight, then ordinary lexicographic sequence order with shorter proper prefix first. A robust implementation can formulate suffix states built from later items backward: taking the current item prepends its original position to the child sequence, and skipping keeps the next suffix record. Store the chosen transition and reconstruct by following it from the capacity-15 root. This avoids assuming that a local take/skip preference establishes global lexicographic order. Print the selected maximum and actual selected weight, then names selected by increasing original positions using the current filter/forward scan (or current final reverse of backward reconstruction). No source modification is produced.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.dart`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 13 | 31 | `  const weights = [10, 3, 2, 3, 5, 5, 6];` |
| 14 | 39 | `  const values = [120, 65, 45, 20, 90, 85, 100];` |
| 15 | 33 | `  final dp = List.generate(8, (_) => List.filled(21, 0));` |
| 16 | 26 | `  for (var i = 1; i <= 7; i++) {` |
| 17 | 27 | `    for (var c = 0; c <= 20; c++) {` |
| 18 | 25 | `      dp[i][c] = dp[i - 1][c];` |
| 19 | 21 | `      if (weights[i - 1] <= c) {` |
| 20 | 17 | `        dp[i][c] = math.max(` |
| 21 | 12 | `          dp[i][c],` |
| 22 | 37 | `          dp[i - 1][c - weights[i - 1]] + values[i - 1],` |
| 23 | 5 | `        );` |
| 24 | 4 | `      }` |
| 25 | 3 | `    }` |
| 26 | 3 | `  }` |
| 27 | 18 | `  final chosen = List.filled(7, false);` |
| 28 | 11 | `  var capacity = 20;` |
| 29 | 26 | `  for (var i = 7; i > 0; i--) {` |
| 30 | 29 | `    if (dp[i][capacity] != dp[i - 1][capacity]) {` |
| 31 | 16 | `      chosen[i - 1] = true;` |
| 32 | 16 | `      capacity -= weights[i - 1];` |
| 33 | 3 | `    }` |
| 34 | 3 | `  }` |
| 35 | 9 | `  final items = [` |
| 36 | 24 | `    for (var i = 0; i < 7; i++)` |
| 37 | 17 | `      if (chosen[i]) names[i],` |
| 38 | 4 | `  ];` |
| 39 | 39 | `  print('max value: ${dp[7][20]}\ntotal weight: ${20 - capacity}');` |
| 40 | 22 | `  print('items: ${items.join(' ')}');` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **520 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 599 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 526 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
