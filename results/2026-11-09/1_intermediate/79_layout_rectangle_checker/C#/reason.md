# Task B selection — C#

## Answer requirements shared across languages

1. Locate the strict separated-pair gap comparison reached by DRC and by CHECK through a registered RULE SPACING value, and explain changing it from < to <=.
2. Explain the shared geometry: signed overlap extents, exact nonnegative gap, unconditional corner-contact violation, and unchanged treatment of overlaps and edge contacts.
3. Trace deterministic pair ordering and violation/count reporting for both entry points.
4. Identify rule-state updates and explain why the spacing queries and the proposed comparison edit do not change rectangle state or undo history.

## Selected source locations

- `Program.cs`: 7, 8, 9, 10, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 187, 189, 199, 200, 201, 202, 203, 204, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 262, 263, 264, 265, 266, 267, 268, 488, 489, 490, 491, 493, 494, 495, 497, 500, 501, 502, 503, 504, 505, 521, 522, 523, 524, 525, 526, 530, 531, 552, 553, 554, 555, 556, 557, 558

## Evidence and language semantics

SortedDictionary uses ordinal names for pair traversal, and Spacing orders by gap then both rectangle names with StringComparer.Ordinal. Both query cases only build output from local lists; RULE writes its separate dictionary. Replace only the strict comparison between the gap and the requested spacing threshold with its inclusive form. Leave the corner-contact alternative unconditional, and leave the separated-kind guard, exact gap computation, ordering keys, and report construction unchanged. The same selected spacing helper is used by direct DRC and by CHECK with the stored spacing rule value, so a single local comparison change serves both paths. RULE stores the threshold in the rule table; query/report code reads rectangle state and does not add a rectangle-edit history entry. No proposed source change is implemented.

## Minimization and alternatives

The excerpt retains the geometry and spacing predicate, ordered layer/pair inputs, both consumers, the spacing-rule storage path, and the state/history evidence needed by the question. Other geometric reports, enclosure/width-rule computations and rectangle editing algorithms are unrelated and omitted. Selecting only the comparison would omit evidence for the second entry point and preservation requirements. Replacing a shared helper instead of independently changing command branches is the smaller change; standard collection sorting, numeric and formatting semantics require no library source.

The excerpt contains 1588 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
