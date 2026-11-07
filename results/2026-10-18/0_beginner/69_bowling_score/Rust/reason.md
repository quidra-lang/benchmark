# Task B selection: 69_bowling_score / Rust

## Common answer requirements

Change the existing frame-order cumulative output into individual frame scores, preserving bonuses, the tenth frame and spacing.

## Supported analysis

Each cumulative value represents the completed frames through that position. Emit the difference from the preceding total, using zero for frame one. This retains bonuses in the frame to which the current calculation already credits them. Subtracting the ninth total from the tenth leaves only the tenth frame contribution. Use the existing write or collection sites, including any separate tenth-frame append. Where a complete frame-local score already exists, emit that score directly. The excerpt for this language uses the frame-local-score alternative.

The excerpt is copied verbatim from `main.rs`, in source order. Retained source lines: 14, 32, 33.

## Minimization and alternatives

Adjacent differences preserve the current scoring calculation and avoid changing the strike/spare and tenth-frame branches. The frame loop, collection or write identify the emission sites. Keeping every branch is a larger alternative needed only if rewriting the scoring calculation. The prior selection used 54 tokens; this selection uses 42 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.

## Current token measurement

Task A: **765 tokens**. Task B: **42 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
