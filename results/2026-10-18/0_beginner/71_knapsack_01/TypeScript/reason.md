# Task B selection: 71_knapsack_01 / TypeScript

## Common answer requirements

Locate capacity/table bounds and reconstruction/output dependencies; explain capacity 15 plus maximum-value, minimum-total-weight, lexicographically smallest increasing original-position sequence tie resolution with proper prefix first, reconstructing from DP and keeping printed names in original order.

## Supported analysis

Replace capacity 20 with 15 at the capacity initialization, loops, final-table lookup and any literal weight calculation; a compact table now has capacities 0..15 (16 columns). The present numeric maximum and inequality-only backtracking do not encode all requested ties. Use DP records containing value, total weight, increasing original item-position sequence, and the corresponding take/skip reconstruction choice; compare records by larger value, then smaller weight, then ordinary lexicographic sequence order with shorter proper prefix first. A robust implementation can formulate suffix states built from later items backward: taking the current item prepends its original position to the child sequence, and skipping keeps the next suffix record. Store the chosen transition and reconstruct by following it from the capacity-15 root. This avoids assuming that a local take/skip preference establishes global lexicographic order. Print the selected maximum and actual selected weight, then names selected by increasing original positions using the current filter/forward scan (or current final reverse of backward reconstruction). No source modification is produced.

The chosen array currently stores item objects; additional sequence metadata should compare original indices, while printing can continue mapping chosen items to names. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.ts`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 7 | 10 | `const capacity = 20;` |
| 8 | 48 | `const dp = Array.from({length: items.length + 1}, () => Array<number>(capacity + 1).fill(0));` |
| 9 | 21 | `items.forEach(({weight, value}, index) => {` |
| 10 | 14 | `  const i = index + 1;` |
| 11 | 26 | `  for (let limit = 0; limit <= capacity; limit++) {` |
| 12 | 24 | `    dp[i][limit] = dp[i - 1][limit];` |
| 13 | 56 | `    if (weight <= limit) dp[i][limit] = Math.max(dp[i][limit], dp[i - 1][limit - weight] + value);` |
| 14 | 3 | `  }` |
| 15 | 4 | `});` |
| 16 | 14 | `const chosen: typeof items = [];` |
| 17 | 9 | `let remaining = capacity;` |
| 18 | 27 | `for (let i = items.length; i > 0; i--) {` |
| 19 | 29 | `  if (dp[i][remaining] !== dp[i - 1][remaining]) {` |
| 20 | 16 | `    chosen.push(items[i - 1]);` |
| 21 | 16 | `    remaining -= items[i - 1].weight;` |
| 22 | 3 | `  }` |
| 23 | 2 | `}` |
| 24 | 7 | `chosen.reverse();` |
| 25 | 26 | `console.log(\`max value: ${dp[items.length][capacity]}\`);` |
| 26 | 41 | `console.log(\`total weight: ${chosen.reduce((sum, item) => sum + item.weight, 0)}\`);` |
| 27 | 34 | `console.log(\`items: ${chosen.map(item => item.name).join(" ")}\`);` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **430 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 608 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 433 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
