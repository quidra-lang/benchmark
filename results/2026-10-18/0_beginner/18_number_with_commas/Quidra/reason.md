# Task B selection: 18_number_with_commas / Quidra

## Common answer requirements

Bind the source input -456789 and trace exact comma grouping, sign placement, and newline.

## Source evidence

The literal contains -456789 and the loop passes it unchanged to the formatter. The group=3 integer format groups the magnitude from the right as 456 and 789, keeping the sign before the digits. The line-output call emits -456,789 followed by a newline.

## Minimization

The other values share the complete source line that establishes the focused input, just as in the Python loop. That source line is retained verbatim. Selected complete lines of `main.qui`: 1, 2, 3.
