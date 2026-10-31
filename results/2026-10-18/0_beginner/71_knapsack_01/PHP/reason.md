# Task B selection: 71_knapsack_01 / PHP

## Common answer requirements

Locate capacity/table bounds and reconstruction/output dependencies; explain capacity 15 plus maximum-value, minimum-total-weight, lexicographically smallest increasing original-position sequence tie resolution with proper prefix first, reconstructing from DP and keeping printed names in original order.

## Supported analysis

Replace capacity 20 with 15 at the capacity initialization, loops, final-table lookup and any literal weight calculation; a compact table now has capacities 0..15 (16 columns). The present numeric maximum and inequality-only backtracking do not encode all requested ties. Use DP records containing value, total weight, increasing original item-position sequence, and the corresponding take/skip reconstruction choice; compare records by larger value, then smaller weight, then ordinary lexicographic sequence order with shorter proper prefix first. A robust implementation can formulate suffix states built from later items backward: taking the current item prepends its original position to the child sequence, and skipping keeps the next suffix record. Store the chosen transition and reconstruct by following it from the capacity-15 root. This avoids assuming that a local take/skip preference establishes global lexicographic order. Print the selected maximum and actual selected weight, then names selected by increasing original positions using the current filter/forward scan (or current final reverse of backward reconstruction). No source modification is produced.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.php`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 7 | 9 | `$capacity = 20;` |
| 8 | 43 | `$table = array_fill(0, count($items) + 1, array_fill(0, $capacity + 1, 0));` |
| 9 | 29 | `foreach ($items as $i => [$name, $weight, $value]) {` |
| 10 | 28 | `    for ($limit = 0; $limit <= $capacity; $limit++) {` |
| 11 | 31 | `        $table[$i + 1][$limit] = $table[$i][$limit];` |
| 12 | 16 | `        if ($weight <= $limit) {` |
| 13 | 61 | `            $table[$i + 1][$limit] = max($table[$i + 1][$limit], $table[$i][$limit - $weight] + $value);` |
| 14 | 4 | `        }` |
| 15 | 3 | `    }` |
| 16 | 2 | `}` |
| 17 | 23 | `$chosen = array_fill(0, count($items), false);` |
| 18 | 9 | `$remaining = $capacity;` |
| 19 | 34 | `for ($i = count($items) - 1; $i >= 0; $i--) {` |
| 20 | 35 | `    if ($table[$i + 1][$remaining] !== $table[$i][$remaining]) {` |
| 21 | 14 | `        $chosen[$i] = true;` |
| 22 | 18 | `        $remaining -= $items[$i][1];` |
| 23 | 3 | `    }` |
| 24 | 2 | `}` |
| 25 | 8 | `$names = [];` |
| 26 | 19 | `foreach ($items as $i => $item) {` |
| 27 | 14 | `    if ($chosen[$i]) {` |
| 28 | 15 | `        $names[] = $item[0];` |
| 29 | 3 | `    }` |
| 30 | 2 | `}` |
| 31 | 3 | `printf(` |
| 32 | 28 | `    "max value: %d\ntotal weight: %d\nitems: %s\n",` |
| 33 | 16 | `    $table[count($items)][$capacity],` |
| 34 | 10 | `    $capacity - $remaining,` |
| 35 | 13 | `    implode(' ', $names),` |
| 36 | 3 | `);` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **498 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 616 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 501 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
