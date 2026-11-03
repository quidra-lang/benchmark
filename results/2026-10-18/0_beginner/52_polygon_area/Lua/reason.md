# Task B selection: 52_polygon_area / Lua

## Common answer requirements

Identify the closing edge in both shoelace and perimeter calculations; trace polygon 2 last-to-first operands and contribution; establish nonnegative half-area and the sequential floating-point perimeter addition order.

## Supported analysis

Polygon 2 ends at (8,2) and starts at (2,1). Wrapping the successor index selects this closing edge for both calculations. Its cross contribution is 8*1-2*2=4; its length is sqrt((8-2)^2+(2-1)^2)=sqrt(37). In polygon order the cross contributions are 8,-12,-31,-34,4, producing -65; absolute magnitude divided by two gives 32.5. The perimeter loop starts from zero and adds edges in vertex order, with the closing edge last. The selected explicit accumulator update preserves that floating-point order rather than replacing it with an unspecified rearranged sum.

i % #vertices + 1 wraps the last one-based vertex to index 1. The final source table records the exact retained boundaries. Multiline declarations/expressions are terminated where needed to distinguish data from processing; selected control/helper scopes use their original lexical terminators. Unrelated branch/display closes are excluded. Indentation is used as a scope guarantee only in indentation-defined languages.

## Source evidence and dependencies

The excerpt is copied from `main.lua`. Original source locations and their exact token costs are listed below. Read the selected lines together: declarations bind the named inputs and accumulators; loop headers establish traversal order and bounds; conditions govern the indented operations; assignments and expressions establish the actual data transformations. A line containing several operations cannot be shortened under the complete-line rule.

| Original line | Tokens | Source evidence |
| --- | ---: | --- |
| 1 | 8 | `local polygons = {` |
| 2 | 35 | `    {{0, 0}, {5, 0}, {6, 4}, {1, 3}},` |
| 3 | 43 | `    {{2, 1}, {0, 4}, {3, 7}, {7, 6}, {8, 2}},` |
| 6 | 16 | `for number, vertices in ipairs(polygons) do` |
| 7 | 19 | `    local twice_area, perimeter = 0, 0.0` |
| 8 | 17 | `    for i, point in ipairs(vertices) do` |
| 9 | 22 | `        local following = vertices[i % #vertices + 1]` |
| 10 | 40 | `        twice_area = twice_area + point[1] * following[2] - following[1] * point[2]` |
| 11 | 36 | `        local dx, dy = point[1] - following[1], point[2] - following[2]` |
| 12 | 29 | `        perimeter = perimeter + math.sqrt(dx * dx + dy * dy)` |
| 13 | 3 | `    end` |
| 14 | 52 | `    io.write(string.format("polygon %d: area=%.1f perimeter=%.3f\n", number, math.abs(twice_area) / 2, perimeter))` |
| 15 | 2 | `end` |

The table supplies the concrete operands, guards, updates, and call connections used by the analysis above. Imports, entry-point boilerplate, unrelated examples, and unrelated reporting are omitted when they add no requested fact. Ordinary scalar assignment, arithmetic, indexing, conditional execution, loop order, and the shown standard-library operations have their documented language meaning. No user-defined helper is assumed to have behavior merely from its name: where its behavior is needed, its relevant definition and operations are included. Task A compilation and correctness are assumed as required by README §2.3; no Task A program was executed.

## Minimization and alternatives

The selected set costs **322 tokens** under `metric/tokenizer.py`'s `tokenize`. The complete original source costs 383 tokens, an alternative that also contains the evidence but adds unrelated context. Restoring omitted standalone structural closing lines gives 324 tokens; the omitted closers finish wrapper/list syntax or other scopes that do not distinguish any requested decision or update. Scope terminators that do distinguish a selected branch, loop, helper definition, or following operation are retained and justified above. Indentation is not treated as a scope guarantee in brace/end languages. Closing lines that contain a substantive operation also remain selected. Each listed substantive line is retained for its input value, dependency binding, traversal rule, decision, state update, affected output operation, or required expression continuation; omitting such evidence would require importing implementation information absent from the excerpt. This is a reviewed lower-token sufficient selection among the relevant sets considered, not a proof of a global mathematical minimum.
