# Task B selection: 31_pascal_triangle / Quidra

The initial row [1] is printed before each update. The two padded copies, [0] followed by row and row followed by 0, are added element by element. This gives row 3 as [1, 3, 3, 1]. Row 4 uses 0+1, 1+3, 3+3, 3+1, and 1+0. The qualified text.join and println produce `1 4 6 4 1`.

Complete main.qui lines: 3, 4, 5, 6, 7. The qualified call identifies the joining API. Neither the import nor any implementation of the documented join and array operations is needed. The benchmark tokenizer counts 63 tokens in this excerpt.

Measurement: Task A 68; Task B 63. Tokenizer: metric/tokenizer.py, unchanged.
