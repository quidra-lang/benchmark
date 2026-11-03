# Task B selection: 71_knapsack_01 / C++

## Common answer requirements

Locate capacity/table bounds and reconstruction/output dependencies; explain capacity 15 plus maximum-value, minimum-total-weight, lexicographically smallest increasing original-position sequence tie resolution with proper prefix first, reconstructing from DP and keeping printed names in original order.

## Supported analysis

Replace capacity 20 with 15 at the capacity initialization, loops, final-table lookup and any literal weight calculation; a compact table now has capacities 0..15 (16 columns). The present numeric maximum and inequality-only backtracking do not encode all requested ties. Use DP records containing value, total weight, increasing original item-position sequence, and the corresponding take/skip reconstruction choice; compare records by larger value, then smaller weight, then ordinary lexicographic sequence order with shorter proper prefix first. A robust implementation can formulate suffix states built from later items backward: taking the current item prepends its original position to the child sequence, and skipping keeps the next suffix record. Store the chosen transition and reconstruct by following it from the capacity-15 root. This avoids assuming that a local take/skip preference establishes global lexicographic order. Print the selected maximum and actual selected weight, then names selected by increasing original positions using the current filter/forward scan (or current final reverse of backward reconstruction). No source modification is produced.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.cpp`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 9 | 75 | `    std::array<int, 7> weights = {10, 3, 2, 3, 5, 5, 6}, values = {120, 65, 45, 20, 90, 85, 100};` |
| 10 | 15 | `    int dp[8][21]{};` |
| 11 | 24 | `    for (int i = 1; i <= 7; i++)` |
| 12 | 28 | `        for (int w = 0; w <= 20; w++) {` |
| 13 | 26 | `            dp[i][w] = dp[i - 1][w];` |
| 14 | 20 | `            if (weights[i - 1] <= w)` |
| 15 | 62 | `                dp[i][w] = std::max(dp[i][w], dp[i - 1][w - weights[i - 1]] + values[i - 1]);` |
| 16 | 4 | `        }` |
| 17 | 16 | `    std::array<bool, 7> chosen{};` |
| 18 | 20 | `    int capacity = 20, total_weight = 0;` |
| 19 | 24 | `    for (int i = 7; i >= 1; i--)` |
| 20 | 30 | `        if (dp[i][capacity] != dp[i - 1][capacity]) {` |
| 21 | 17 | `            chosen[i - 1] = true;` |
| 22 | 17 | `            capacity -= weights[i - 1];` |
| 23 | 19 | `            total_weight += weights[i - 1];` |
| 24 | 4 | `        }` |
| 25 | 52 | `    std::cout << "max value: " << dp[7][20] << "\ntotal weight: " << total_weight << "\nitems:";` |
| 26 | 24 | `    for (int i = 0; i < 7; i++)` |
| 27 | 11 | `        if (chosen[i])` |
| 28 | 21 | `            std::cout << ' ' << names[i];` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **509 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 617 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 511 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
