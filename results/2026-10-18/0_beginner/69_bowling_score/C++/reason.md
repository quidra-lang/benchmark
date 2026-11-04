# Task B selection: 69_bowling_score / C++

## Common answer requirements

Change the existing frame-order cumulative output into individual frame scores, preserving bonuses, the tenth frame and spacing.

## Supported analysis

Each cumulative value represents the completed frames through that position. Emit the difference from the preceding total, using zero for frame one. This retains bonuses in the frame to which the current calculation already credits them. Subtracting the ninth total from the tenth leaves only the tenth frame contribution. Use the existing write or collection sites, including any separate tenth-frame append. Where a complete frame-local score already exists, emit that score directly. The excerpt for this language uses the frame-local-score alternative.

The excerpt is copied verbatim from `main.cpp`, in source order. Retained source lines: 14, 29, 30.

## Minimization and alternatives

Adjacent differences preserve the current scoring calculation and avoid changing the strike/spare and tenth-frame branches. The frame loop, collection or write identify the emission sites. Keeping every branch is a larger alternative needed only if rewriting the scoring calculation. The prior selection used 68 tokens; this selection uses 56 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
