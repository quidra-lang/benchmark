# Task B selection — JavaScript

## Answer requirements shared across languages

1. Locate the strict separated-pair gap comparison reached by DRC and by CHECK through a registered RULE SPACING value, and explain changing it from < to <=.
2. Explain the shared geometry: signed overlap extents, exact nonnegative gap, unconditional corner-contact violation, and unchanged treatment of overlaps and edge contacts.
3. Trace deterministic pair ordering and violation/count reporting for both entry points.
4. Identify rule-state updates and explain why the spacing queries and the proposed comparison edit do not change rectangle state or undo history.

## Selected source locations

- `main.js`: 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 21, 22, 23, 24, 25, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 343, 344, 345, 346, 347, 348, 413, 414, 415, 566, 567, 569, 570, 571, 572, 573, 574, 575, 579, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 607, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 631, 632, 633, 634, 635, 636

## Evidence and language semantics

The comparator uses gap, first name and second name in order; compare is included. The modifying-command guard excludes both queries and RULE, while the only shown history append is inside that guard. Map replacement of a rule does not update rectangles. Replace only the strict comparison between the gap and the requested spacing threshold with its inclusive form. Leave the corner-contact alternative unconditional, and leave the separated-kind guard, exact gap computation, ordering keys, and report construction unchanged. The same selected spacing helper is used by direct DRC and by CHECK with the stored spacing rule value, so a single local comparison change serves both paths. RULE stores the threshold in the rule table; query/report code reads rectangle state and does not add a rectangle-edit history entry. No proposed source change is implemented.

## Minimization and alternatives

The excerpt retains the geometry and spacing predicate, ordered layer/pair inputs, both consumers, the spacing-rule storage path, and the state/history evidence needed by the question. Other geometric reports, enclosure/width-rule computations and rectangle editing algorithms are unrelated and omitted. Selecting only the comparison would omit evidence for the second entry point and preservation requirements. Replacing a shared helper instead of independently changing command branches is the smaller change; standard collection sorting, numeric and formatting semantics require no library source.

The excerpt contains 1685 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
