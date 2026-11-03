# Task B selection: 87_gaussian_elimination / Quidra

## Common answer requirements

[Modification analysis]

Using the Task A source as evidence, explain which parts would need to change and how to satisfy the proposed requirements below. Do not edit the program or produce modified source code.

Proposed requirements:
Print every solution value with exactly six digits after the decimal point instead of four, rounding half up at the seventh decimal place. Preserve negative signs for negative values and use a single zero before the decimal point when the integer part is zero. Keep all elimination and back-substitution computations in double precision with the original operation order and pivot rules. All other Task A requirements remain unchanged.

## Answer supported by the selection

Change the output interpolation suffix `frac=4` to `frac=6`. The same real64 solution value is then rendered with six fractional digits, preserving its sign and ordinary decimal integer part, including a zero before the decimal point for magnitudes below one. The computed solution values do not fall on a six-place rounding tie, so this gives the requested half-up rounded results for these systems. Elimination, pivot selection, back substitution and their operation order do not change.

## Source evidence and minimization

The single output statement contains the existing numeric value, variable label, spacing and precision setting. These are sufficient to identify the precision-only presentation change. Selecting the elimination or back-substitution implementation would add unrelated unchanged computation.

Locations in main source: L31.

All selected lines are complete, verbatim and in source order. The selected source, the question, and documented language/library semantics support the answer. The full source is a sufficient alternative but includes the unrelated material identified above; the retained selection is a reviewed lower-token sufficient candidate, without a claim of exhaustive global minimality.

Measurement: Task A 601; Task B 24. Tokenizer: metric/tokenizer.py, unchanged. These counts and source selections do not establish compilation or execution of Task A.
