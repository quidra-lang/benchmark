# Task B selection: 45_anagram_groups / Python

## Common answer requirements

Locate the per-group filter while preserving group creation and the order of retained groups and words.

## Source evidence

The dictionary-values loop visits groups in insertion order and unpacking prints each group in its current order. Add a length-at-least-two guard at the per-group print site. Leave group creation and the iteration order intact.

## Minimization

The loop header is needed to show the filter applies once per group and preserves the order in which groups are visited. The unchanged signature and grouping computations are outside the change. Selected complete lines of `main.py`: 19, 20.

## Current token measurement

Task A: **147 tokens**. Task B: **19 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
