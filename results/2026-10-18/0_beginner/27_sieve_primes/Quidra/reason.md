# Task B selection: 27_sieve_primes / Quidra

The boolean flags start true. Marking by p from 2p never targets 7 from p=7, and no smaller p divides it. The 7 pass starts at 14 and marks 14, 21, 28, 35, 42 and 49 false. The final scan pushes exactly the remaining true numbers, and the documented chunks and text.join pass those numbers to println, so 7 prints and 49 does not.

Complete main.qui lines: 1, 4, 7, 8, 9, 10, 12, 13, 14, 16, 17, 18. The explicit text namespace identifies join. The collections import is needed for the chunks extension. The empty declaration supplies no distinct fact about the final list membership for 7 and 49. The benchmark tokenizer counts 155 tokens in this excerpt.

Measurement: Task A 202; Task B 155. Tokenizer: metric/tokenizer.py, unchanged.

The marking range inherits int from p and its integer bounds; omitting the repeated range type preserves the marked multiples.
