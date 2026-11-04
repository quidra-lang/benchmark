# Task B selection: 22_char_frequency / Lua

Count uppercase and lowercase ASCII letters separately, ignore other characters, and print only present letters in uppercase-then-lowercase order with their original case and line format.

The table starts empty; the lowercase input and pattern currently merge or exclude capitals. Match both ASCII ranges against the original input, scan the uppercase codes before the lowercase codes, and preserve the existing presence check and character output.

Complete main.lua lines: 1, 2, 3, 4, 5, 6. Retain the folding, eligibility, counter and output evidence rather than inferring case, ordering or sparsity from a variable name. Unchanged setup and source text are unnecessary unless a complete line combines them with a necessary operation. The benchmark tokenizer counts 155 tokens in this excerpt.
