Keep the original integer placements count and convert only for reporting to thousands. Use real division by 1000 and format three fractional digits, changing the label to "placements (thousands): ". Each exact placement contributes 0.001 thousand, so three digits represent the original integer count without rounding it.

placements starts at integer zero and increments once per candidate placement. Replace only the final interpolation with a floating fdiv(1000) and %.3f formatter before puts; integer /1000 would truncate.

The integer placements declaration/increment and reporting site identify the preserved counter and changed unit. Sudoku constraint logic does not affect the conversion from count to thousands.
