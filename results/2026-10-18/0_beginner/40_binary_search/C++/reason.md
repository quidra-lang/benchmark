# Task B selection: 40_binary_search / C++

Trace the probes and bound updates for the given target, show why the sentinel stays unset, and derive the complete output.

Starting with bounds (0, 15), probe 7 (31) and raise the lower bound to 8; probe 11 (53) and lower the upper bound to 10; probe 9 (42) and raise the lower bound to 10; probe 10 (47) and raise it to 11. The interval is now empty, so the loop stops without setting the success index. The output is `50: probes 7 11 9 10 -> not found`.

The question provides target 50, but the searched array and the index arithmetic must come from source. The equality assignment and result test show that a failed search leaves the original sentinel. Probe recording and string joining or sequential writes fix the output spacing. The success-only break or output body is unnecessary for this trace.

Source: `main.cpp`, original lines 5, 7–13, 15–21, 23–24. The previous excerpt measures 351 tokens; this evidence set measures 306 tokens.

## Current token measurement

Task A: **414 tokens**. Task B: **306 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
