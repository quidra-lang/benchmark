# Task B — signal events and next-period estimation

The answer requirements are identical across languages: map I/MR ending sample positions to subgroup numbers; establish sorting and duplicate-number handling; explain the rolling last-end gap test rather than a total-span cap; establish inclusive event membership/number for an unsignalled interior subgroup; show which complete subgroup interval contributes to event summaries while signal records remain the actual signals; trace exclusion from next-period points, including retained phase-one points and I/MR sample expansion.

## Source evidence and guarantees

Signal.subgroup maps I/MR by chart strings. Set and sorted remove duplicate subgroup IDs and order them. Event is explicitly a final class: last in events.last is a reference to the existing event, so changing its end really extends the interval. Its contains and length are inclusive. Only real signals fill event.signals/counts, but the covered array slice includes unsignalled interior groups for summaries. eventOf and the subgroup row use the same interval. The phase2 suffix excludes phase1; next-period ids combine retained estimates with only nil-event groups, expanding each I_MR group to all samples before limits.

Writing n for the source subgroup size, I/MR map the signal's ending sample e to floor((e−1)/n)+1; other monitored charts already use subgroup endpoints. For example n=5,e=6 maps to subgroup2, including an MR whose preceding sample belongs to subgroup1. Duplicate subgroup numbers do not create distinct event intervals, although distinct original signals can still be counted as signals. With gap2 and phase-two signalled groups3,6,6,9, the rolling gaps are6−3−1=2 and9−6−1=2: one event spans3..9 even though its total span exceeds2. Groups4,5,7,8 have no own signal but lie inside that event. They receive its number, contribute their measurements to interval-based summaries, and cannot be added as event-free phase-two data for the next-period estimates. This does not manufacture signal records for those interior groups. The next-period input combines the retained phase-one data with event-free phase-two groups; I/MR expand the latter to every sample in each accepted subgroup.

## Necessity and minimization

- `main.swift`: 49, 50, 51, 52, 53, 60, 62, 63, 113, 161, 205, 206, 207, 208, 209, 211, 212, 218, 219, 220, 221, 222, 224, 225, 258, 259, 260, 261, 262, 263, 264, 325, 326
- `run_rules.swift`: 12

The selected endpoint mapping, deduplication/order, last-end update, inclusive membership, interval aggregation and proposal input selection each establish a different required boundary. A point-membership check alone would not prove summary or estimation behavior, so those consumers remain. Entire monitoring/rule algorithms, control-limit formulas, formatting, event-type tie resolution and unrelated attribute/capability calculations were considered and excluded: the question concerns data membership and propagation, rather than their numeric formulas. Language/library container ordering and slicing guarantees are used directly; custom interval/membership helpers are retained where needed. Full source lines and original per-file order are preserved, with no invented context or separators.

The excerpt contains 981 tokens with `metric/tokenizer.py`. A fresh excerpt-only review checked every requirement, especially an interior unsignalled subgroup, deduplicated grouping versus real signals, the rolling gap and the next-period filter. No Task A source was changed and execution correctness was not claimed.
