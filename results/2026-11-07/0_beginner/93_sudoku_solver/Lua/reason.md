Keep the original integer placements count and convert only for reporting to thousands. Use real division by 1000 and format three fractional digits, changing the label to "placements (thousands): ". Each exact placement contributes 0.001 thousand, so three digits represent the original integer count without rounding it.

The integer counter and update need no change. At string.format, use placements/1000 (not //) and %.3f, then io.write the line; no count mutation is required.

The integer placements declaration/increment and reporting site identify the preserved counter and changed unit. Sudoku constraint logic does not affect the conversion from count to thousands.
