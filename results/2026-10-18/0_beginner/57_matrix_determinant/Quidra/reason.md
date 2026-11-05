# Task B selection: 57_matrix_determinant / Quidra

## Answer requirements

Locate every recursive expansion; explain second-row minor/coefficient selection and alternating sign reversal while preserving the one-entry base case and integer arithmetic.

## Answer supported by the selected source

For each column, replace the first-row-removing matrix[1:] source with rows consisting of the first row followed by rows starting at the third row; select the coefficient from matrix[1][j]. For zero-based j the second-row cofactor is negative when j is even and positive when j is odd, reversing the shown conditional. The recursive call applies the same function to every minor. Keep n==1 and matrix[0][0] unchanged. The int parameter elements, inferred integer term and total, and int return contract preserve integer arithmetic.

## Evidence and alternatives

The function signature, size, base case, column loop, minor, coefficient, recursive call and parity update identify the affected sites and preserved integer contract. Matrix literals, output and final return of the already-computed total are unaffected. A collection generation over core row.indices() supplies exactly the existing columns; the prior range-generation spelling is rejected by the pinned compiler.

Selected complete main.qui source lines: 1, 2, 3, 4, 5, 6, 7, 8, 9. Every selected line is copied verbatim, exactly once per source location, in source order. The excerpt need not compile independently. A separate excerpt-only review checked every answer requirement using only the excerpt, the question, and documented language/package semantics. The full source and the previous implementation/excerpt were considered; unrelated source was excluded as described above. This is a reviewed necessary-and-sufficient candidate among the alternatives considered, without a claim of exhaustive global mathematical minimality.

## Measurement and validation

Using unchanged metric/tokenizer.py (SHA-256 3a2649e33a55f135c2fe88568f50c5d81e81a5fe01f9c7af22bba8da55b1d941): Task A 414 tokens; Task B 158 tokens. Original values: Task A 425; Task B 167. Task B proposed modifications have not been implemented. Lexical counts or excerpt review do not by themselves establish compilation or correctness.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 414; Task B 158.

Measurement: Task A 414; Task B 158. Tokenizer: metric/tokenizer.py, unchanged.

The column range inherits nat from n, which is the natural length of matrix; the omitted range type does not change the integer determinant arithmetic.
