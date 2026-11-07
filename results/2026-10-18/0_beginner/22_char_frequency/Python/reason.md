# Task B selection: 22_char_frequency / Python

## Common answer requirements

Show how to separate ASCII uppercase and lowercase letters, retain only letters present, and print their original case in uppercase-then-lowercase order.

## Source evidence

The Counter generator currently lowercases the input and accepts only a through z. Filter the original characters with two ASCII ranges instead. Sorting the resulting character keys still orders uppercase before lowercase, and the output interpolates the key directly without changing its case.

## Minimization

The input literal is unchanged. The existing formatter is needed to verify that the preserved case reaches the displayed label. Selected complete lines of `main.py`: 1, 4, 5, 6.

## Current token measurement

Task A: **98 tokens**. Task B: **74 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
