# Task B selection: 71_knapsack_01 / Lua

## Common answer requirements

Locate capacity/table bounds and reconstruction/output dependencies; explain capacity 15 plus maximum-value, minimum-total-weight, lexicographically smallest increasing original-position sequence tie resolution with proper prefix first, reconstructing from DP and keeping printed names in original order.

## Supported analysis

Replace capacity 20 with 15 at the capacity initialization, loops, final-table lookup and any literal weight calculation; a compact table now has capacities 0..15 (16 columns). The present numeric maximum and inequality-only backtracking do not encode all requested ties. Use DP records containing value, total weight, increasing original item-position sequence, and the corresponding take/skip reconstruction choice; compare records by larger value, then smaller weight, then ordinary lexicographic sequence order with shorter proper prefix first. A robust implementation can formulate suffix states built from later items backward: taking the current item prepends its original position to the child sequence, and skipping keeps the next suffix record. Store the chosen transition and reconstruct by following it from the capacity-15 root. This avoids assuming that a local take/skip preference establishes global lexicographic order. Print the selected maximum and actual selected weight, then names selected by increasing original positions using the current filter/forward scan (or current final reverse of backward reconstruction). No source modification is produced.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.lua`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 5 | 24 | `local capacity, dp = 20, {[0] = {}}` |
| 6 | 27 | `for weight = 0, capacity do dp[0][weight] = 0 end` |
| 7 | 16 | `for i, item in ipairs(items) do` |
| 8 | 11 | `    dp[i] = {}` |
| 9 | 14 | `    for weight = 0, capacity do` |
| 10 | 24 | `        dp[i][weight] = dp[i - 1][weight]` |
| 11 | 66 | `        if item[2] <= weight then dp[i][weight] = math.max(dp[i][weight], dp[i - 1][weight - item[2]] + item[3]) end` |
| 12 | 3 | `    end` |
| 13 | 2 | `end` |
| 14 | 15 | `local chosen, remaining = {}, capacity` |
| 15 | 18 | `for i = #items, 1, -1 do` |
| 16 | 27 | `    if dp[i][remaining] ~= dp[i - 1][remaining] then` |
| 17 | 11 | `        chosen[i] = true` |
| 18 | 18 | `        remaining = remaining - items[i][2]` |
| 19 | 3 | `    end` |
| 20 | 2 | `end` |
| 21 | 9 | `local names = {}` |
| 22 | 16 | `for i, item in ipairs(items) do` |
| 23 | 29 | `    if chosen[i] then names[#names + 1] = item[1] end` |
| 24 | 2 | `end` |
| 25 | 35 | `io.write(string.format("max value: %d\ntotal weight: %d\nitems: %s\n",` |
| 26 | 32 | `    dp[#items][capacity], capacity - remaining, table.concat(names, " ")))` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **404 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 517 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 406 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
