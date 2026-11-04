# Task B selection — 28_matrix_row_col_sums / Lua

## Common answer requirements

Locate the row, column and whole-matrix reductions and the three destination fields whose values change to maxima.

## Source evidence

The selected row and column axes connect each element to the current row and column summary. Replace their sum operations with maxima, using data-derived starting values when accumulating, and use the maximum over all entries for the final field. The selected output sites show where the three summary values are used.

## Minimization

Selected complete lines of `main.lua`: L2, L3, L4, L5, L6, L7, L9, L10, L11, L12, L13, L14. The original loop boundaries establish which updates happen per element, which occur once per row and which produce the final summary line. The sample matrix and the unchanged printing of original row elements are not needed to locate the changed fields.

The selected excerpt measures **206 tokens** with `metric/tokenizer.py`.
