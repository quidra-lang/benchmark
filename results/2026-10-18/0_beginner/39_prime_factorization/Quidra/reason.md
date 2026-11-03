# Task B selection: 39_prime_factorization / Quidra

Trace trial division of 9973, the square stopping bound, unchanged remainder, and the single residual factor/output.

The fixture, remaining/divisor/exponent state, both trial loops and increment establish that no divisor 2..99 changes 9973. At divisor100 the square bound fails. The residual greater-than-one branch pushes its decimal spelling and join emits one factor without separators or an exponent. The positive-exponent formatting body cannot execute for this trace, so it is omitted.

Collections `.push` explicitly mutates an array binding by appending one element; array value copies remain independent. Its standard-library contract suffices; its implementation is not required. The selection retains the prior answer dependencies with the corresponding writable operations and their import. A full-source alternative adds unrelated lines.

Complete source lines: 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 18, 19, 20, 21.
All lines are verbatim and in source order.
Tokenizer: Task A 281; Task B 228.
Execution is checked separately; these source-line checks alone do not establish compilation or a global minimum.
