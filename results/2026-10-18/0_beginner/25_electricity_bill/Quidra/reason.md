# Task B selection: 25_electricity_bill / Quidra

The 900 yen basic charge is set once. At 120 kWh, Suzuki is charged 120 × 30 and no higher tier, totaling 4,500 yen. At 300 kWh, Tanaka is charged 120 × 30 and 180 × 36, totaling 10,980 yen, with no top tier.

The first branch charges all the usage at 30 only when the usage is at most 120. The next branch charges 120 at 30 and only the remainder at 36. The otherwise branch containing the 40 rate is bypassed at both inputs.

Complete main.qui lines: 5, 6, 7, 8, 9, 10, 11. The conditions and tier quantities explain why no higher rate is applied to the whole input, and why the branch above 300 is skipped. The question supplies both usage values; input lookup, household totals and printing are unnecessary. The benchmark tokenizer counts 122 tokens in this excerpt.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 259; Task B 122.

Measurement: Task A 259; Task B 122. Tokenizer: metric/tokenizer.py, unchanged.
