# Task B selection: 25_electricity_bill / Zig

The 900 yen basic charge is set once. At 120 kWh, Suzuki is charged 120 × 30 and no higher tier, totaling 4,500 yen. At 300 kWh, Tanaka is charged 120 × 30 and 180 × 36, totaling 10,980 yen, with no top tier.

The minimum caps first-tier usage at 120. The second branch charges no more than 180 of the remaining usage, and the top tier runs only above 300. Neither input enters it.

Complete main.zig lines: 11, 12, 13, 14, 15. The conditions and tier quantities explain why no higher rate is applied to the whole input, and why the branch above 300 is skipped. The question supplies both usage values; input lookup, household totals and printing are unnecessary. The benchmark tokenizer counts 129 tokens in this excerpt.

## Current token measurement

Task A: **452 tokens**. Task B: **129 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
