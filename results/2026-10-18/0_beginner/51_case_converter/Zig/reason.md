# Task B selection: 51_case_converter / Zig

## Common answer requirements

Add ASCII-uppercase normalized words joined by underscores and append the fifth field to the existing per-identifier output.

## Source evidence

The style loop emits the existing fields and visits the normalized words in words[0..count]. After the loop and before its newline, append “, upper=” and reuse this same slice, adding underscores only between words and converting every byte with the standard ASCII uppercase operation.

## Minimization

Adding the fifth field at the newline needs neither writer setup nor capitalization logic for other styles. The existing word loop and separator condition show how to preserve the filtered word sequence.

Selected complete lines of `main.zig`: 39, 44–48, 54–56. The prior excerpt measured 407 tokens; this excerpt measures 167 with `metric/tokenizer.py`.

## Current token measurement

Task A: **913 tokens**. Task B: **167 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
