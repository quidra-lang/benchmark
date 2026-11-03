# Task B selection: 60_shopping_receipt / C

## Common answer requirements

Trace actual food items into the category subtotal and its integer tax; explain where truncation occurs and why it is per category; follow that food tax to final payment and distinguish earlier untaxed item printing.

## Supported analysis

Food items are milk 198*2=396, bread 248*1=248, apple 128*4=512, and eggs 268*1=268. The food category reaches 1424 before tax; 1424*8/100=113.92 is truncated to 113 by the shown integer division/floor operation. Item lines print price times quantity before category tax calculation, so they are untaxed subtotals. Flooring the individual food taxes would instead give 31+19+40+21=111; the source does not do that. The selected final-payment expression adds the category subtotals and category taxes, so the food tax contributes exactly once. General subtotal/tax processing is shown only where it shares the final payment dependency or a complete source line.

All operands in the tax expression are int, so / performs truncating integer division; there is no separate cast after the fact. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.c`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 4 | 43 | `    const char *names[] = {"milk", "notebook", "bread", "apple", "detergent", "eggs"};` |
| 5 | 65 | `    int prices[] = {198, 165, 248, 128, 437, 268}, quantities[] = {2, 3, 1, 4, 1, 1};` |
| 6 | 46 | `    int category[] = {0, 1, 0, 0, 1, 0}, totals[2] = {0}, taxes[2];` |
| 7 | 26 | `    for (int i = 0; i < 6; i++) {` |
| 8 | 21 | `        int subtotal = prices[i] * quantities[i];` |
| 9 | 14 | `        totals[category[i]] += subtotal;` |
| 10 | 47 | `        printf("%s %d x %d = %d\n", names[i], prices[i], quantities[i], subtotal);` |
| 11 | 3 | `    }` |
| 12 | 24 | `    taxes[0] = totals[0] * 8 / 100;` |
| 13 | 25 | `    taxes[1] = totals[1] * 10 / 100;` |
| 14 | 60 | `    printf("food: %d yen, tax %d yen\ngeneral: %d yen, tax %d yen\ntotal: %d yen\n", totals[0], taxes[0],` |
| 15 | 42 | `        totals[1], taxes[1], totals[0] + totals[1] + taxes[0] + taxes[1]);` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **416 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 443 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 418 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
