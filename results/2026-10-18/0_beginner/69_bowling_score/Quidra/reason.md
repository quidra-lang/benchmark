# Task B selection: 69_bowling_score / Quidra

## Common answer requirements

Locate cumulative scoring and separate it into frame scores without changing the roll cursor, bonus attribution, or tenth-frame handling.

## Source evidence

The normal strike path adds ten and the next two rolls while advancing the cursor one roll. The nonstrike path adds its two rolls, with the next roll only for a spare, and advances two. The tenth frame sums all rolls from its current cursor. Compute a separate value for each frame with those same rules, and emit or collect each frame value instead of the running total.

## Minimization

Retain the branches and every cumulative update that must be redirected to the individual frame score. Game input literals are independent of the change. Selected complete lines of `main.qui`: 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26.
