# Task B selection — Java

## Answer requirements shared across languages

1. Identify the layout-produced, retained content origin and width/height, and distinguish them from the border rectangle used by HIT.
2. Identify the HIT predicate replacement that excludes border/padding while preserving displayed filtering, viewport rejection, half-open bounds and empty zero-width/height behavior.
3. Establish document-order selection of the latest matching element and root-to-element path or none output; connect existing content geometry without changing layout or element order.

## Selected source locations

- `Main.java`: 44, 45, 46, 47, 48, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 351, 352, 353, 388, 576, 577, 646, 647, 648, 649, 650, 651, 652, 653, 654, 733

## Evidence and language semantics

The selected layout assignments retain content width/height and the final element origin. The content geometry formulas add the left/top border and padding offsets to that origin and use the content extents, whereas HIT currently consumes border geometry. Under the proposal, only that HIT rectangle acquisition or its coordinate/extent expressions change. Preserve the shown/displayed condition, viewport error branch, matching order and path output. Existing <= / < comparisons describe half-open rectangles; if either content extent is zero, the lower and upper comparisons cannot both hold, so there is no hit. No layout/order mutation is needed.

ArrayList iteration preserves insertion order. The HIT loop overwrites hit, and path.add(0, id) walks parent references into a root-first path. Replace x/y/bw()/bh() in the predicate with cx()/cy()/cw/ch; accessors prove the required distinction. Object field writes retain layout geometry.

## Minimization and alternatives

The comparison and output branches cannot be removed without losing required boundary/order/path evidence. The content formulas and dimension storage cannot be replaced by Task A prose. Rendering, style parsing, unrelated command dispatch and detailed unchanged layout solvers are excluded because this is a connection between retained geometry and HIT, not a request to calculate a particular layout. A call-only selection was rejected because custom geometry helpers have no language-guaranteed meaning. The final excerpt was reviewed alone against all three shared requirements.

The small geometry accessors are less expensive than selecting BOX/render processing. No standard-library collection implementation is needed; full layout algorithms cannot change where this predicate consumes already retained values.

The excerpt contains 948 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
