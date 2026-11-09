# Task B selection — Python

## Answer requirements shared across languages

1. Locate the strict separated-pair gap comparison reached by DRC and by CHECK through a registered RULE SPACING value, and explain changing it from < to <=.
2. Explain the shared geometry: signed overlap extents, exact nonnegative gap, unconditional corner-contact violation, and unchanged treatment of overlaps and edge contacts.
3. Trace deterministic pair ordering and violation/count reporting for both entry points.
4. Identify rule-state updates and explain why the spacing queries and the proposed comparison edit do not change rectangle state or undo history.

## Selected source locations

- `main.py`: 11, 49, 50, 51, 52, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 119, 120, 121, 122, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 321, 328, 329, 332, 333, 334, 335, 336, 340, 341, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 578, 579, 580, 645, 646, 647, 650, 651, 673, 676, 677, 680, 681, 684, 685, 686

## Evidence and language semantics

combinations receives name-sorted rectangles; tuple sorting orders gap then both names. The explicit MODIFYING set excludes RULE, DRC and CHECK, and the history append is gated by that set. Replace only the strict comparison between the gap and the requested spacing threshold with its inclusive form. Leave the corner-contact alternative unconditional, and leave the separated-kind guard, exact gap computation, ordering keys, and report construction unchanged. The same selected spacing helper is used by direct DRC and by CHECK with the stored spacing rule value, so a single local comparison change serves both paths. RULE stores the threshold in the rule table; query/report code reads rectangle state and does not add a rectangle-edit history entry. No proposed source change is implemented.

## Minimization and alternatives

The excerpt retains the geometry and spacing predicate, ordered layer/pair inputs, both consumers, the spacing-rule storage path, and the state/history evidence needed by the question. Other geometric reports, enclosure/width-rule computations and rectangle editing algorithms are unrelated and omitted. Selecting only the comparison would omit evidence for the second entry point and preservation requirements. Replacing a shared helper instead of independently changing command branches is the smaller change; standard collection sorting, numeric and formatting semantics require no library source.

The excerpt contains 1280 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
