# Task B selection: 28_matrix_row_col_sums / R

Replace each row, each column, and the whole matrix reduction with maxima. Preserve the original row fields and keep each summary in its current six-character field and line.

addmargins supplies row and column summaries and the corner summary in one operation. Use maximum as its margin function; the corner is the maximum of maxima. Its result still goes through the existing width-six row formatter.

Complete main.R lines: 7, 8, 9. The loop/data dependencies connect each changed reduction to its axis; the affected fields identify destinations. Raw matrix values and individual unchanged element-output code are not needed for the modification. The benchmark tokenizer counts 77 tokens in this excerpt.
