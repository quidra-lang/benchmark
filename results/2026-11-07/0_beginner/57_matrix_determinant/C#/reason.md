# Task B selection: 57_matrix_determinant / C#

The base returns the single integer entry. Each column builds a minor dropping the first row and that column, multiplies its recursive determinant by the corresponding top entry, and alternately adds/subtracts the term. Matrix 1 first term is 2*(4*3-(-2)*6)=48. Signed integer storage/operations retain exact terms here; no real division or rounding occurs in the operation.

Keep the determinant operation and only the first matrix literal needed for the concrete term. Other matrices and output formatting do not affect the signed recursive calculation.

Selected complete source lines in `Program.cs`: 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 23. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
