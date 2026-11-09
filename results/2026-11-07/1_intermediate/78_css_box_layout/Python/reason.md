# Task B selection — Python

## Answer requirements shared across languages

1. Identify the layout-produced, retained content origin and width/height, and distinguish them from the border rectangle used by HIT.
2. Identify the HIT predicate replacement that excludes border/padding while preserving displayed filtering, viewport rejection, half-open bounds and empty zero-width/height behavior.
3. Establish document-order selection of the latest matching element and root-to-element path or none output; connect existing content geometry without changing layout or element order.

## Selected source locations

- `main.py`: 153, 154, 155, 156, 157, 164, 165, 166, 168, 169, 170, 194, 195, 205, 207, 208, 209, 210, 211, 321, 323, 324, 325, 326, 327, 328, 329, 330, 331, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 803, 804, 811, 812, 813, 836, 939, 940, 941, 942, 943, 944, 945, 946, 947, 948, 949, 950, 951, 952, 989, 992

## Evidence and language semantics

The selected layout assignments retain content width/height and the final element origin. The content geometry formulas add the left/top border and padding offsets to that origin and use the content extents, whereas HIT currently consumes border geometry. Under the proposal, only that HIT rectangle acquisition or its coordinate/extent expressions change. Preserve the shown/displayed condition, viewport error branch, matching order and path output. Existing <= / < comparisons describe half-open rectangles; if either content extent is zero, the lower and upper comparisons cannot both hold, so there is no hit. No layout/order mutation is needed.

Python list iteration and the input comprehension retain order; assignment to target replaces the previous match. `contains` supplies the actual half-open comparisons. Replace the border_box argument with content_box; tuple unpacking retains the stored content sizes. The selected frame/size accessors prove that the current border rectangle adds padding and border to cw/ch.

## Minimization and alternatives

The comparison and output branches cannot be removed without losing required boundary/order/path evidence. The content formulas and dimension storage cannot be replaced by Task A prose. Rendering, style parsing, unrelated command dispatch and detailed unchanged layout solvers are excluded because this is a connection between retained geometry and HIT, not a request to calculate a particular layout. A call-only selection was rejected because custom geometry helpers have no language-guaranteed meaning. The final excerpt was reviewed alone against all three shared requirements.

Compared with reconstructing all four edges at the HIT call, reusing the selected content_box helper is smaller and already expresses both offsets. Final-position assignments suffice to identify retained x/y; unrelated placement rules are unaffected.

The excerpt contains 1082 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
