# Task B selection — Dart

## Answer requirements shared across languages

1. Identify the layout-produced, retained content origin and width/height, and distinguish them from the border rectangle used by HIT.
2. Identify the HIT predicate replacement that excludes border/padding while preserving displayed filtering, viewport rejection, half-open bounds and empty zero-width/height behavior.
3. Establish document-order selection of the latest matching element and root-to-element path or none output; connect existing content geometry without changing layout or element order.

## Selected source locations

- `main.dart`: 105, 106, 107, 108, 109, 110, 259, 260, 287, 448, 449, 456, 457, 459, 460, 461, 462, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 580

## Evidence and language semantics

The selected layout assignments retain content width/height and the final element origin. The content geometry formulas add the left/top border and padding offsets to that origin and use the content extents, whereas HIT currently consumes border geometry. Under the proposal, only that HIT rectangle acquisition or its coordinate/extent expressions change. Preserve the shown/displayed condition, viewport error branch, matching order and path output. Existing <= / < comparisons describe half-open rectangles; if either content extent is zero, the lower and upper comparisons cannot both hold, so there is no hit. No layout/order mutation is needed.

Dart List iteration preserves insertion order and the loop overwrites selected for each match. boxes(...).content derives its origin by adding padding to the border-offset padding box and uses cw/ch. Use that rectangle in the HIT predicate; nullable selected and path.reversed preserve none/root-first output.

## Minimization and alternatives

The comparison and output branches cannot be removed without losing required boundary/order/path evidence. The content formulas and dimension storage cannot be replaced by Task A prose. Rendering, style parsing, unrelated command dispatch and detailed unchanged layout solvers are excluded because this is a connection between retained geometry and HIT, not a request to calculate a particular layout. A call-only selection was rejected because custom geometry helpers have no language-guaranteed meaning. The final excerpt was reviewed alone against all three shared requirements.

The boxes content constructor is necessary source evidence; its margin calculation is omitted because it does not affect content. Layout writes replace a much larger selection of unchanged flow algorithms.

The excerpt contains 1048 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
