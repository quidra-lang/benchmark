# Task B selection: 55_grid_paths / Quidra

## Common answer requirements

Add one down-right move to both path counts, checking only the destination for obstacles and preserving the existing outputs.

## Source evidence

The row sweep keeps one DP slot per column. Its old value is the count from above; the already updated slot on its left gives the left count. Save each old slot before either the passable update or the blocked reset, carrying it into the next column as that cell’s old upper-left count. At positive row and column indices add this count only in the passable destination branch. Reset the carried value per row, preserve the single empty path at the start, and retain the last-column result and both calls. An adjacent orthogonal cell need not be passable.

## Minimization

The final-slot return confirms that the rolling-state extension keeps the output path; replacing the one-dimensional table would require a different return. Grid literals do not govern the recurrence.

Selected complete lines of `main.qui`: 1, 3–11, 13. The prior excerpt measured 156 tokens; this excerpt measures 160 with `metric/tokenizer.py`.

Measurement: Task A 211; Task B 160. Tokenizer: metric/tokenizer.py, unchanged.
