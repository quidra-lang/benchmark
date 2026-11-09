# Task B selection — C#

## Answer requirements shared across languages

1. Identify the layout-produced, retained content origin and width/height, and distinguish them from the border rectangle used by HIT.
2. Identify the HIT predicate replacement that excludes border/padding while preserving displayed filtering, viewport rejection, half-open bounds and empty zero-width/height behavior.
3. Establish document-order selection of the latest matching element and root-to-element path or none output; connect existing content geometry without changing layout or element order.

## Selected source locations

- `Program.cs`: 38, 39, 40, 41, 42, 43, 44, 45, 333, 335, 336, 378, 600, 601, 674, 675, 676, 677, 678, 679, 680, 681, 682, 683, 778

## Evidence and language semantics

The selected layout assignments retain content width/height and the final element origin. The content geometry formulas add the left/top border and padding offsets to that origin and use the content extents, whereas HIT currently consumes border geometry. Under the proposal, only that HIT rectangle acquisition or its coordinate/extent expressions change. Preserve the shown/displayed condition, viewport error branch, matching order and path output. Existing <= / < comparisons describe half-open rectangles; if either content extent is zero, the lower and upper comparisons cannot both hold, so there is no hit. No layout/order mutation is needed.

LINQ LastOrDefault returns the last predicate match in List enumeration order and returns null on no match. Use Cx/Cy/Cw/Ch in the existing predicate; its Bw/Bh accessors show the current inclusion of frame edges. Insert(0, id) and Parent produce root-first output.

## Minimization and alternatives

The comparison and output branches cannot be removed without losing required boundary/order/path evidence. The content formulas and dimension storage cannot be replaced by Task A prose. Rendering, style parsing, unrelated command dispatch and detailed unchanged layout solvers are excluded because this is a connection between retained geometry and HIT, not a request to calculate a particular layout. A call-only selection was rejected because custom geometry helpers have no language-guaranteed meaning. The final excerpt was reviewed alone against all three shared requirements.

The four property definitions and two layout writes are smaller than full BOX/render implementations. LastOrDefault has documented ordering/null behavior, so no LINQ implementation is needed. Content accessors already express the new origin.

The excerpt contains 919 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
