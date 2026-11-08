# Task B selection — PHP

## Answer requirements shared across languages

1. Identify the layout-produced, retained content origin and width/height, and distinguish them from the border rectangle used by HIT.
2. Identify the HIT predicate replacement that excludes border/padding while preserving displayed filtering, viewport rejection, half-open bounds and empty zero-width/height behavior.
3. Establish document-order selection of the latest matching element and root-to-element path or none output; connect existing content geometry without changing layout or element order.

## Selected source locations

- `main.php`: 27, 28, 29, 30, 38, 39, 40, 41, 42, 43, 44, 45, 411, 413, 439, 695, 696, 705, 706, 707, 708, 713, 800, 801, 802, 803, 804, 805, 806, 807, 808, 809, 810, 811, 812, 813, 814, 815, 816, 907

## Evidence and language semantics

The selected layout assignments retain content width/height and the final element origin. The content geometry formulas add the left/top border and padding offsets to that origin and use the content extents, whereas HIT currently consumes border geometry. Under the proposal, only that HIT rectangle acquisition or its coordinate/extent expressions change. Preserve the shown/displayed condition, viewport error branch, matching order and path output. Existing <= / < comparisons describe half-open rectangles; if either content extent is zero, the lower and upper comparisons cannot both hold, so there is no hit. No layout/order mutation is needed.

PHP array insertion order is preserved by foreach and [] appending. Retain the last matching object and the array_unshift parent path. Use content geometry from boxes, or the equivalent x+border-left+padding-left / y+border-top+padding-top / cw / ch fields, in the current predicate. Objects preserve field identity through assignments.

## Minimization and alternatives

The comparison and output branches cannot be removed without losing required boundary/order/path evidence. The content formulas and dimension storage cannot be replaced by Task A prose. Rendering, style parsing, unrelated command dispatch and detailed unchanged layout solvers are excluded because this is a connection between retained geometry and HIT, not a request to calculate a particular layout. A call-only selection was rejected because custom geometry helpers have no language-guaranteed meaning. The final excerpt was reviewed alone against all three shared requirements.

Only the content entry and bindings from boxes are needed; margin/padding entries do not determine the new extents. The direct content-field alternative is smaller to explain than including the renderer.

The excerpt contains 950 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
