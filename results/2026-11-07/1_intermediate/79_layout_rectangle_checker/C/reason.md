# Task B selection — C

## Answer requirements shared across languages

1. Locate the strict separated-pair gap comparison reached by DRC and by CHECK through a registered RULE SPACING value, and explain changing it from < to <=.
2. Explain the shared geometry: signed overlap extents, exact nonnegative gap, unconditional corner-contact violation, and unchanged treatment of overlaps and edge contacts.
3. Trace deterministic pair ordering and violation/count reporting for both entry points.
4. Identify rule-state updates and explain why the spacing queries and the proposed comparison edit do not change rectangle state or undo history.

## Selected source locations

- `main.c`: 65, 77, 78, 79, 81, 82, 83, 110, 111, 112, 114, 115, 116, 138, 139, 140, 172, 173, 174, 175, 177, 178, 179, 180, 181, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 414, 415, 416, 417, 418, 419, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 432, 433, 434, 455, 456, 457, 458, 459, 460, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 485, 486, 487, 488, 495, 496, 497, 498, 742, 743, 745, 746, 747, 748, 749, 750, 751, 752, 753, 754, 758, 760, 761, 777, 778, 779, 780, 781

## Evidence and language semantics

The rectangle insertion sort and its strcmp comparator provide name order. spacing_compare explicitly compares gap and both names; only the local Pair result buffer is sorted. CHECK uses kind 1 and the same read-only spacing body; the rule comparator preserves deterministic rule order. Replace only the strict comparison between the gap and the requested spacing threshold with its inclusive form. Leave the corner-contact alternative unconditional, and leave the separated-kind guard, exact gap computation, ordering keys, and report construction unchanged. The same selected spacing helper is used by direct DRC and by CHECK with the stored spacing rule value, so a single local comparison change serves both paths. RULE stores the threshold in the rule table; query/report code reads rectangle state and does not add a rectangle-edit history entry. No proposed source change is implemented.

## Minimization and alternatives

The excerpt retains the geometry and spacing predicate, ordered layer/pair inputs, both consumers, the spacing-rule storage path, and the state/history evidence needed by the question. Other geometric reports, enclosure/width-rule computations and rectangle editing algorithms are unrelated and omitted. Selecting only the comparison would omit evidence for the second entry point and preservation requirements. Replacing a shared helper instead of independently changing command branches is the smaller change; standard collection sorting, numeric and formatting semantics require no library source. Whitespace-only lines outside source literals and explicit line continuations are omitted: they contribute tokens but no evidence for the answer. Literal content is preserved, and files with ambiguous quote or multiline-literal syntax are left unchanged by this step.

The excerpt contains 2234 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
