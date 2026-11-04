# Task B selection: 69_bowling_score / Quidra

## Common answer requirements

Change the existing frame-order cumulative output into individual frame scores, preserving bonuses, the tenth frame and spacing.

## Supported analysis

Each cumulative value represents the completed frames through that position. Emit the difference from the preceding total, using zero for frame one. This retains bonuses in the frame to which the current calculation already credits them. Subtracting the ninth total from the tenth leaves only the tenth frame contribution. Use the existing write or collection sites, including any separate tenth-frame append. Where a complete frame-local score already exists, emit that score directly. Initialize the previous total to zero at the selected per-game label; after each frame print the difference and save the current total.

The excerpt is copied verbatim from `main.qui`, in source order. Retained source lines: 13, 14, 26. Additional evidence is on line 13: `print("game {game + 1}:")`.

## Minimization and alternatives

Adjacent differences preserve the current scoring calculation and avoid changing the strike/spare and tenth-frame branches. The frame loop, collection or write identify the emission sites. Keeping every branch is a larger alternative needed only if rewriting the scoring calculation. The prior selection used 188 tokens; this selection uses 40 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
