# Task B selection: 28_matrix_row_col_sums / J

Replace each row, each column, and the whole matrix reduction with maxima. Preserve the original row fields and keep each summary in its current six-character field and line.

The row expression appends a rank-one sum to each original row, the column expression reduces across rows, and the last reduction is over columns. Replace those three plus reductions with max reductions using the same ranks and append positions. The 6.0 format stays.

Complete main.ijs lines: 2, 3, 4, 5. The loop/data dependencies connect each changed reduction to its axis; the affected fields identify destinations. Raw matrix values and individual unchanged element-output code are not needed for the modification. The benchmark tokenizer counts 48 tokens in this excerpt.
