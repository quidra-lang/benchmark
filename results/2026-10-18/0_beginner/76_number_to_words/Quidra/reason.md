# Task B selection: 76_number_to_words / Quidra

Trace 0, 71000 and 300019; distinguish whole zero from omitted zero components; explain the joins without extra spaces.

The small-number/tens tables and under_thousand body establish every word. The top-level zero case, thousand branch, nonzero remainder guard and joins show why71000 has no zero suffix and300019 has no empty hundred separator. Only nonempty components are pushed. The unrelated display setup and inputs outside the required traces are omitted where complete-line selection permits.

Collections `.push` explicitly mutates an array binding by appending one element; array value copies remain independent. Its standard-library contract suffices; its implementation is not required. The selection retains the prior answer dependencies with the corresponding writable operations and their import. A full-source alternative adds unrelated lines.

Complete source lines: 1, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 25, 26, 27, 28, 29, 30, 31, 32.
All lines are verbatim and in source order.
Tokenizer: Task A 549; Task B 483.
Execution is checked separately; these source-line checks alone do not establish compilation or a global minimum.
