# Task B selection — J

## Answer requirements shared across languages

1. Identify the layout-produced, retained content origin and width/height, and distinguish them from the border rectangle used by HIT.
2. Identify the HIT predicate replacement that excludes border/padding while preserving displayed filtering, viewport rejection, half-open bounds and empty zero-width/height behavior.
3. Establish document-order selection of the latest matching element and root-to-element path or none output; connect existing content geometry without changing layout or element order.

## Selected source locations

- `main.ijs`: 114, 115, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 331, 332, 540, 545, 546, 547, 548, 549, 550, 551, 552, 614, 615, 714, 715, 716, 717, 718, 719, 720, 721, 722, 723, 724, 725, 726, 788

## Evidence and language semantics

The selected layout assignments retain content width/height and the final element origin. The content geometry formulas add the left/top border and padding offsets to that origin and use the content extents, whereas HIT currently consumes border geometry. Under the proposal, only that HIT rectangle acquisition or its coordinate/extent expressions change. Preserve the shown/displayed condition, viewport error branch, matching order and path output. Existing <= / < comparisons describe half-open rectangles; if either content extent is zero, the lower and upper comparisons cannot both hold, so there is no hit. No layout/order mutation is needed.

J indexed amendment stores content width/height in Geometry columns 0/1 and final origin in 4/5. contentBox returns border plus padding offsets and those stored extents. Replace borderBox i at the HIT acquisition with contentBox i. i.#ElementIDs is ascending, so target is the latest match; prepend plus Parents gives the root-first path.

## Minimization and alternatives

The comparison and output branches cannot be removed without losing required boundary/order/path evidence. The content formulas and dimension storage cannot be replaced by Task A prose. Rendering, style parsing, unrelated command dispatch and detailed unchanged layout solvers are excluded because this is a connection between retained geometry and HIT, not a request to calculate a particular layout. A call-only selection was rejected because custom geometry helpers have no language-guaranteed meaning. The final excerpt was reviewed alone against all three shared requirements.

Selected box projections and Geometry writes avoid all unchanged layout distribution calculations. The paddingBox definition is needed because contentBox calls it; a name alone would not establish its border offset.

The excerpt contains 798 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
