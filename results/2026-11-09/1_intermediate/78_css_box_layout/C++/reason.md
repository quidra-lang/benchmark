# Task B selection — C++

## Answer requirements shared across languages

1. Identify the layout-produced, retained content origin and width/height, and distinguish them from the border rectangle used by HIT.
2. Identify the HIT predicate replacement that excludes border/padding while preserving displayed filtering, viewport rejection, half-open bounds and empty zero-width/height behavior.
3. Establish document-order selection of the latest matching element and root-to-element path or none output; connect existing content geometry without changing layout or element order.

## Selected source locations

- `main.cpp`: 145, 147, 148, 153, 536, 537, 538, 555, 643, 644, 645, 651, 652, 653, 656, 657, 658, 659, 660, 661, 662, 663, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 837

## Evidence and language semantics

The selected layout assignments retain content width/height and the final element origin. The content geometry formulas add the left/top border and padding offsets to that origin and use the content extents, whereas HIT currently consumes border geometry. Under the proposal, only that HIT rectangle acquisition or its coordinate/extent expressions change. Preserve the shown/displayed condition, viewport error branch, matching order and path output. Existing <= / < comparisons describe half-open rectangles; if either content extent is zero, the lower and upper comparisons cannot both hold, so there is no hit. No layout/order mutation is needed.

std::vector preserves insertion order, the forward index scan replaces found on every match, std::reverse and join produce the root-first path. Rect::contains gives explicit half-open bounds. Pass "content" instead of "border" to rectangle; its content branch offsets the existing origin and uses cw/ch. References update the same Element storage.

## Minimization and alternatives

The comparison and output branches cannot be removed without losing required boundary/order/path evidence. The content formulas and dimension storage cannot be replaced by Task A prose. Rendering, style parsing, unrelated command dispatch and detailed unchanged layout solvers are excluded because this is a connection between retained geometry and HIT, not a request to calculate a particular layout. A call-only selection was rejected because custom geometry helpers have no language-guaranteed meaning. The final excerpt was reviewed alone against all three shared requirements.

The rectangle helper is the compact source for both boxes. Its margin branch and intermediate padding width/height adjustments are unnecessary: content replaces both extents. Layout dimension writes identify retention without selecting unchanged flex/grid internals.

The excerpt contains 1031 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
