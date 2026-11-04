# Task B selection: 53_closest_pair / Quidra

## Common answer requirements

Print the two stored squared distances as decimal integers, preserving pair selection, tie handling, labels, and layout.

## Source evidence

The squared-distance expression and the selected-pair updates show that the score stored for each extreme is already the value to print. The strict improvement tests preserve the earlier encounter when scores tie. Remove the square root/conversion at the output path and use ordinary interpolation of the stored integers and remove both :frac=4 modifiers. Preserve labels, point-name formatting and line order.

## Minimization

Print-only evidence would not establish that the value supplied to the square root is the squared value used by the comparisons. The strict comparisons and score stores suffice without the point literals or a trace of all pairs.

Selected complete lines of `main.qui`: 1, 7–8, 17–19, 22–23, 26–28. The prior excerpt measured 153 tokens; this excerpt measures 178 with `metric/tokenizer.py`.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 452; Task B 178.

Measurement: Task A 452; Task B 178. Tokenizer: metric/tokenizer.py, unchanged.
