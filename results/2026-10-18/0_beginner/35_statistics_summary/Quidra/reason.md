# Task B selection: 35_statistics_summary / Quidra

## Common answer requirements

[Modification analysis]

Using the Task A source as evidence, explain which parts would need to change and how to satisfy the proposed requirements below. Do not edit the program or produce modified source code.

Proposed requirements:
Modify the program to report the sample standard deviation instead of the population standard deviation. Keep the mean and the specified accumulation of squared differences unchanged, but divide their sum by 10, the number of elements minus one, before taking the square root.

Keep the stdev: label, half-up rounding to exactly three decimal places, and every other reported statistic unchanged. All other Task A requirements remain unchanged.

## Source evidence and minimization

Subtract 1.0 from count only in the denominator inside the selected sqrt call. The count declaration establishes the array length and its real64 type. The Math import supplies the square-root operation. No mean, square-accumulation, mode or output formatting change is required, so those unchanged statements are excluded.

Locations in main source: L2, L5, L17.

The selected lines are complete, verbatim and in source order. Library semantics are used only with the required binding/type evidence. A separate pass checked that the excerpt supports each requested fact; unrelated output or unchanged implementations are excluded. Replacing this selection with the full enclosing span or whole source adds tokens without adding necessary answer evidence. This is a reviewed sufficient selection, not a proof of global mathematical minimality.

Measurement: Task A 317; Task B 35. Tokenizer: metric/tokenizer.py, unchanged. These source-token checks do not establish compilation or execution of Task A.
