# Task B selection for 13_diamond_pattern in Quidra

The loop visits the inclusive range `1:n`, followed by the descending range `n>:1`. The latter excludes `n`, so the widest row appears only once.

With the given size of five, line five uses `i = 5`. Repeating a space `n - i` times gives zero spaces, and repeating `*` `2 * i - 1` times gives nine asterisks. Line six uses `i = 4`, giving one space and seven asterisks.

Lines 2 and 3 of `main.qui` give the iteration order and the two repetition counts. Both are needed. The size declaration repeats a fact supplied in the question.

The source contains 64 tokens for Task A and the excerpt contains 58 tokens for Task B.
