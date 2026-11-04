# Task B selection: 28_matrix_row_col_sums / Quidra

## Common answer requirements

Locate the three reductions that become maxima and identify the field formatting that stays fixed.

## Source evidence

The row sum is emitted at the end of each original row. The columns array starts at zero and adds each row elementwise. Change that accumulation to column-wise maxima with an initial row or equivalent initialization. The final loop prints each column value in a width-six field, and the last field currently sums the column totals. It should report the maximum of the column maxima, with the same width and newline.

## Minimization

The existing row-element print statements are unchanged. The column field statement is needed because its value now represents a maximum, and the final width-six field is emitted separately. Selected complete lines of `main.qui`: 1, 4, 5, 6, 9, 10, 11, 12.
