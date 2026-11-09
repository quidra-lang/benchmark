# Task B — signal events and next-period estimation

The answer requirements are identical across languages: map I/MR ending sample positions to subgroup numbers; establish sorting and duplicate-number handling; explain the rolling last-end gap test rather than a total-span cap; establish inclusive event membership/number for an unsignalled interior subgroup; show which complete subgroup interval contributes to event summaries while signal records remain the actual signals; trace exclusion from next-period points, including retained phase-one points and I/MR sample expansion.

## Source evidence and guarantees

signalGroup maps indexes4/5 to I/MR using chartNames; familyNames identifies index2. A map bitmap records unique signalled subgroup IDs and the subsequent ascending integer loop supplies ordering. The rolling Events[n−1].End condition extends an interval, and eventOf uses inclusive start/end with one-based indexes or0. Only real signals increment Total/Counts; summary computation iterates all interval groups. The subgroup writer derives an event number independently of signal count. Proposals append a copy of retained indexes and only event-free phase-two groups; the inclusive numbers helper expands I_MR samples before familyLimits.

Writing n for the source subgroup size, I/MR map the signal's ending sample e to floor((e−1)/n)+1; other monitored charts already use subgroup endpoints. For example n=5,e=6 maps to subgroup2, including an MR whose preceding sample belongs to subgroup1. Duplicate subgroup numbers do not create distinct event intervals, although distinct original signals can still be counted as signals. With gap2 and phase-two signalled groups3,6,6,9, the rolling gaps are6−3−1=2 and9−6−1=2: one event spans3..9 even though its total span exceeds2. Groups4,5,7,8 have no own signal but lie inside that event. They receive its number, contribute their measurements to interval-based summaries, and cannot be added as event-free phase-two data for the next-period estimates. This does not manufacture signal records for those interior groups. The next-period input combines the retained phase-one data with event-free phase-two groups; I/MR expand the latter to every sample in each accepted subgroup.

## Necessity and minimization

- `main.go`: 16, 26, 45, 46, 64, 65, 66, 67, 68, 70, 71, 72, 73, 99
- `dataset.go`: 17, 18

The selected endpoint mapping, deduplication/order, last-end update, inclusive membership, interval aggregation and proposal input selection each establish a different required boundary. A point-membership check alone would not prove summary or estimation behavior, so those consumers remain. Entire monitoring/rule algorithms, control-limit formulas, formatting, event-type tie resolution and unrelated attribute/capability calculations were considered and excluded: the question concerns data membership and propagation, rather than their numeric formulas. Language/library container ordering and slicing guarantees are used directly; custom interval/membership helpers are retained where needed. Full source lines and original per-file order are preserved, with no invented context or separators.

The excerpt contains 1310 tokens with `metric/tokenizer.py`. A fresh excerpt-only review checked every requirement, especially an interior unsignalled subgroup, deduplicated grouping versus real signals, the rolling gap and the next-period filter. No Task A source was changed and execution correctness was not claimed.
