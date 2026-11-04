# Task B selection: 25_electricity_bill / C

The 900 yen basic charge is set once. At 120 kWh, Suzuki is charged 120 × 30 and no higher tier, totaling 4,500 yen. At 300 kWh, Tanaka is charged 120 × 30 and 180 × 36, totaling 10,980 yen, with no top tier.

The first term caps its quantity at 120; the second applies only above 120 and is capped at 180 kWh, while the last applies only above 300. Both requested inputs bypass the last addition.

Complete main.c lines: 7, 8, 9, 10, 11, 12. The conditions and tier quantities explain why no higher rate is applied to the whole input, and why the branch above 300 is skipped. The question supplies both usage values; input lookup, household totals and printing are unnecessary. The benchmark tokenizer counts 145 tokens in this excerpt.
