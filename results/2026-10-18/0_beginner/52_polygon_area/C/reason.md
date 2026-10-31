# Task B selection: 52_polygon_area / C

## Common answer requirements

Identify the closing edge in both shoelace and perimeter calculations; trace polygon 2 last-to-first operands and contribution; establish nonnegative half-area and the sequential floating-point perimeter addition order.

## Supported analysis

Polygon 2 ends at (8,2) and starts at (2,1). Wrapping the successor index selects this closing edge for both calculations. Its cross contribution is 8*1-2*2=4; its length is sqrt((8-2)^2+(2-1)^2)=sqrt(37). In polygon order the cross contributions are 8,-12,-31,-34,4, producing -65; absolute magnitude divided by two gives 32.5. The perimeter loop starts from zero and adds edges in vertex order, with the closing edge last. The selected explicit accumulator update preserves that floating-point order rather than replacing it with an unspecified rearranged sum.

 The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.c`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 6 | 51 | `    int polygons[3][7][2] = {{{0, 0}, {5, 0}, {6, 4}, {1, 3}},` |
| 7 | 50 | `                             {{2, 1}, {0, 4}, {3, 7}, {7, 6}, {8, 2}},` |
| 8 | 67 | `                             {{0, 0}, {8, 0}, {8, 6}, {5, 6}, {4, 3}, {3, 6}, {0, 6}}};` |
| 9 | 19 | `    int sizes[] = {4, 5, 7};` |
| 10 | 26 | `    for (int k = 0; k < 3; k++) {` |
| 11 | 11 | `        int twice = 0;` |
| 12 | 11 | `        double perimeter = 0;` |
| 13 | 30 | `        for (int i = 0; i < sizes[k]; i++) {` |
| 14 | 25 | `            int j = (i + 1) % sizes[k];` |
| 15 | 37 | `            int x = polygons[k][i][0], y = polygons[k][i][1];` |
| 16 | 37 | `            int nx = polygons[k][j][0], ny = polygons[k][j][1];` |
| 17 | 27 | `            int dx = x - nx, dy = y - ny;` |
| 18 | 22 | `            twice += x * ny - nx * y;` |
| 19 | 30 | `            perimeter += sqrt((double)(dx * dx + dy * dy));` |
| 20 | 4 | `        }` |
| 21 | 12 | `        twice = abs(twice);` |
| 22 | 46 | `        printf("polygon %d: area=%.1f perimeter=%.3f\n", k + 1, twice / 2.0, perimeter);` |
| 23 | 3 | `    }` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **508 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 553 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 510 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
