# Task B selection — Kotlin

## Answer requirements shared across languages

1. Locate the strict separated-pair gap comparison reached by DRC and by CHECK through a registered RULE SPACING value, and explain changing it from < to <=.
2. Explain the shared geometry: signed overlap extents, exact nonnegative gap, unconditional corner-contact violation, and unchanged treatment of overlaps and edge contacts.
3. Trace deterministic pair ordering and violation/count reporting for both entry points.
4. Identify rule-state updates and explain why the spacing queries and the proposed comparison edit do not change rectangle state or undo history.

## Selected source locations

- `main.kt`: 14, 15, 16, 33, 34, 35, 36, 37, 38, 39, 40, 41, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 235, 246, 247, 248, 252, 253, 254, 255, 256, 257, 258, 260, 261, 262, 263, 264, 265, 266, 267, 325, 326, 327, 328, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 492, 493, 494, 495, 496, 497, 500, 501, 514, 515, 516, 517

## Evidence and language semantics

The sortedMap provides name order and compareBy/thenBy sorts violations by gap and both names. Relation computes signed common extents. The modifying-command guard and early return keep rule/query paths outside history writes. Replace only the strict comparison between the gap and the requested spacing threshold with its inclusive form. Leave the corner-contact alternative unconditional, and leave the separated-kind guard, exact gap computation, ordering keys, and report construction unchanged. The same selected spacing helper is used by direct DRC and by CHECK with the stored spacing rule value, so a single local comparison change serves both paths. RULE stores the threshold in the rule table; query/report code reads rectangle state and does not add a rectangle-edit history entry. No proposed source change is implemented.

## Minimization and alternatives

The excerpt retains the geometry and spacing predicate, ordered layer/pair inputs, both consumers, the spacing-rule storage path, and the state/history evidence needed by the question. Other geometric reports, enclosure/width-rule computations and rectangle editing algorithms are unrelated and omitted. Selecting only the comparison would omit evidence for the second entry point and preservation requirements. Replacing a shared helper instead of independently changing command branches is the smaller change; standard collection sorting, numeric and formatting semantics require no library source.

The excerpt contains 1756 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
