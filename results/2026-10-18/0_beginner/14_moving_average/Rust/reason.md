# Task B selection: 14_moving_average / Rust

## Answer requirements

Locate the edits needed to select the five-day window, compute its real mean and label the first output day correctly.

## Evidence and answer

Change windows(3) to windows(5), i + 3 to i + 5 and the real-valued divisor 3.0 to 5.0. The windows iterator covers the length-five slices in order, enumerate starts at zero, and the f64 conversion before division preserves real division. These three sites control the requested window, day number and mean; println! and its existing two-place display string require no edits.

## Minimization

Selected complete lines of `main.rs`: 3, 6, 7. The excerpt preserves their text, indentation and order.

Retaining the unchanged display call and format line costs extra tokens. Retaining the iterator alone would omit the day offset and divisor, both of which change. The previous excerpt contained 85 tokens; the selected excerpt contains **63 tokens** using `metric/tokenizer.py`.

## Current token measurement

Task A: **157 tokens**. Task B: **60 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
