# Task B selection — C++

## Answer requirements shared across languages

1. Locate the strict separated-pair gap comparison reached by DRC and by CHECK through a registered RULE SPACING value, and explain changing it from < to <=.
2. Explain the shared geometry: signed overlap extents, exact nonnegative gap, unconditional corner-contact violation, and unchanged treatment of overlaps and edge contacts.
3. Trace deterministic pair ordering and violation/count reporting for both entry points.
4. Identify rule-state updates and explain why the spacing queries and the proposed comparison edit do not change rectangle state or undo history.

## Selected source locations

- `main.cpp`: 18, 19, 20, 21, 22, 23, 24, 25, 26, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 294, 295, 296, 297, 304, 305, 306, 307, 308, 317, 318, 319, 320, 525, 526, 527, 528, 534, 535, 536, 537, 539, 540, 541, 542, 543, 544, 545, 546, 556, 557, 558, 564, 565, 566, 567, 568, 571, 572, 573, 574, 588, 589, 590, 591, 592, 593

## Evidence and language semantics

The std::map of rectangles provides name order; tuple sorting supplies gap/name/name order. Both spacing consumers call a function taking const rectangle references; on_layer is const, and rule registration only assigns rules. Geometry helpers and Rect width/height are included. Replace only the strict comparison between the gap and the requested spacing threshold with its inclusive form. Leave the corner-contact alternative unconditional, and leave the separated-kind guard, exact gap computation, ordering keys, and report construction unchanged. The same selected spacing helper is used by direct DRC and by CHECK with the stored spacing rule value, so a single local comparison change serves both paths. RULE stores the threshold in the rule table; query/report code reads rectangle state and does not add a rectangle-edit history entry. No proposed source change is implemented.

## Minimization and alternatives

The excerpt retains the geometry and spacing predicate, ordered layer/pair inputs, both consumers, the spacing-rule storage path, and the state/history evidence needed by the question. Other geometric reports, enclosure/width-rule computations and rectangle editing algorithms are unrelated and omitted. Selecting only the comparison would omit evidence for the second entry point and preservation requirements. Replacing a shared helper instead of independently changing command branches is the smaller change; standard collection sorting, numeric and formatting semantics require no library source.

The excerpt contains 1752 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
