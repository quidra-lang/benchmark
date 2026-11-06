# Task B selection for 87_gaussian_elimination

The output interpolation is the only site that changes. Change the fractional precision from `.4` to `.6` and preserve the computed real64 value, sign, and variable label. The solution values for the specified systems do not fall on a six-place rounding tie, so the existing formatter suffices for these outputs. Elimination and back substitution are outside the selected change.

Selected complete lines in order are 30.

Task A uses 550 tokens. Task B uses 20 tokens.

Measurement: Task A 550; Task B 20. Tokenizer: metric/tokenizer.py, unchanged.

The elimination ranges inherit int from n and the preceding range variables; the omitted types do not change pivoting, arithmetic or output.
