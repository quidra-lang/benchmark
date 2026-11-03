# Task B selection: 61_coin_change_dp / Lua

## Common answer requirements

Locate ways initialization and update order; explain amount-first dynamic programming with one empty sequence and one contribution per possible final coin, keeping other metrics and output fields unchanged.

## Supported analysis

Retain ways at amount zero equal to one and all positive amounts initially zero. Replace coin-outer iteration with increasing amount-outer iteration; for each amount, iterate every denomination not exceeding it and add ways[amount-coin]. This partitions sequences by final coin and therefore distinguishes different orders, while the current coin-outer pass counts combinations. Start amount iteration at one and apply the coin<=amount guard to avoid negative predecessor indexing. Keep the minimum-count and greedy computations separate and retain their existing fields. Only the ways state and its recurrence need change; unchanged minimum/greedy implementations and printed formatting are not needed to locate that change.

The loop initializing ways[value]=0 shares a complete line with minimum initialization; keep the initialization but remove/replace only the later ways coin-outer pass. A new per-amount ways update may be placed in an increasing amount pass. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.lua`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 3 | 31 | `    local minimums, ways = {[0] = 0}, {[0] = 1}` |
| 4 | 14 | `    for value = 1, amount do` |
| 5 | 24 | `        minimums[value], ways[value] = amount + 1, 0` |
| 9 | 3 | `    end` |
| 10 | 17 | `    for _, coin in ipairs(coins) do` |
| 11 | 40 | `        for value = coin, amount do ways[value] = ways[value] + ways[value - coin] end` |
| 12 | 3 | `    end` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **132 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 381 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 141 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
