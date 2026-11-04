# Task B selection: 22_char_frequency / Julia

Count uppercase and lowercase ASCII letters separately, ignore other characters, and print only present letters in uppercase-then-lowercase order with their original case and line format.

The input is lowercased and the loop considers only a–z. Count against the original string and enumerate A–Z then a–z instead. Equality against the current character excludes all others, and the existing positive guard prints only matches with the same case.

Complete main.jl lines: 1, 2, 3, 4. Retain the folding, eligibility, counter and output evidence rather than inferring case, ordering or sparsity from a variable name. Unchanged setup and source text are unnecessary unless a complete line combines them with a necessary operation. The benchmark tokenizer counts 79 tokens in this excerpt.
