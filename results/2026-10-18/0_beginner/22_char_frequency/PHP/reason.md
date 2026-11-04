# Task B selection: 22_char_frequency / PHP

Count uppercase and lowercase ASCII letters separately, ignore other characters, and print only present letters in uppercase-then-lowercase order with their original case and line format.

Remove strtolower and accept both ASCII ranges of the byte codes from count_chars. Its nonzero-count mode omits absent bytes; keep ascending byte order explicitly if needed and print the actual byte via chr with the unchanged format.

Complete main.php lines: 3, 4, 5. Retain the folding, eligibility, counter and output evidence rather than inferring case, ordering or sparsity from a variable name. Unchanged setup and source text are unnecessary unless a complete line combines them with a necessary operation. The benchmark tokenizer counts 99 tokens in this excerpt.
