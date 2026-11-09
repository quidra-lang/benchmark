# Task B — signal events and next-period estimation

The answer requirements are identical across languages: map I/MR ending sample positions to subgroup numbers; establish sorting and duplicate-number handling; explain the rolling last-end gap test rather than a total-span cap; establish inclusive event membership/number for an unsignalled interior subgroup; show which complete subgroup interval contributes to event summaries while signal records remain the actual signals; trace exclusion from next-period points, including retained phase-one points and I/MR sample expansion.

## Source evidence and guarantees

Signal.subgroup identifies I/MR by their chart strings. distinct().sorted() produces unique ascending numbers; events.last().end is mutable and gets the latest accepted group. Event.contains and eventOf use inclusive membership; event.signals filters actual signals, while covered=groups.subList(start−1,end) includes every intervening subgroup in summary aggregates. Phase2 is the group suffix after phase1. The free list filters null eventOf, then I_MR expands each group using an inclusive IntRange; ids appends those to retained estimates before limits. The subgroup row obtains eventOf(group.number)?.number independently of its own signal count.

Writing n for the source subgroup size, I/MR map the signal's ending sample e to floor((e−1)/n)+1; other monitored charts already use subgroup endpoints. For example n=5,e=6 maps to subgroup2, including an MR whose preceding sample belongs to subgroup1. Duplicate subgroup numbers do not create distinct event intervals, although distinct original signals can still be counted as signals. With gap2 and phase-two signalled groups3,6,6,9, the rolling gaps are6−3−1=2 and9−6−1=2: one event spans3..9 even though its total span exceeds2. Groups4,5,7,8 have no own signal but lie inside that event. They receive its number, contribute their measurements to interval-based summaries, and cannot be added as event-free phase-two data for the next-period estimates. This does not manufacture signal records for those interior groups. The next-period input combines the retained phase-one data with event-free phase-two groups; I/MR expand the latter to every sample in each accepted subgroup.

## Necessity and minimization

- `main.kt`: 21, 22, 29, 31, 58, 94, 133, 134, 135, 136, 137, 139, 140, 146, 147, 148, 149, 150, 152, 153, 184, 185, 186, 187, 188, 189, 190, 245
- `run_rules.kt`: 3

The selected endpoint mapping, deduplication/order, last-end update, inclusive membership, interval aggregation and proposal input selection each establish a different required boundary. A point-membership check alone would not prove summary or estimation behavior, so those consumers remain. Entire monitoring/rule algorithms, control-limit formulas, formatting, event-type tie resolution and unrelated attribute/capability calculations were considered and excluded: the question concerns data membership and propagation, rather than their numeric formulas. Language/library container ordering and slicing guarantees are used directly; custom interval/membership helpers are retained where needed. Full source lines and original per-file order are preserved, with no invented context or separators.

The excerpt contains 873 tokens with `metric/tokenizer.py`. A fresh excerpt-only review checked every requirement, especially an interior unsignalled subgroup, deduplicated grouping versus real signals, the rolling gap and the next-period filter. No Task A source was changed and execution correctness was not claimed.
