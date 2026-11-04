# Task B selection: 49_bracket_balance / TypeScript

## Common answer requirements

Change the post-scan error for leftover openers; preserve full-string indexing, immediate mismatches, balanced results, and formatting.

## Source evidence

The full input scan supplies the position used by each push and by the immediate closing-error branch. The bracket mapping and stack-top test identify the symbol field of an entry. Store each opener with its original position; continue testing the symbol at the top, popping successful matches and reporting the closing position on an empty stack or wrong top. Store the scan’s zero-based index directly. At the post-scan branch, when there was no earlier failure and the stack is nonempty, use the bottom entry’s stored position instead of the length. Scanning before bracket filtering counts spaces. The sentinel and output handling stay the same.

## Minimization

The unchanged input texts and output formatting do not affect the new representation or the error assignment. The matching evidence shows which comparison must still use the symbol after the stack gains a position.

Selected complete lines of `main.ts`: 5, 7–21. The prior excerpt measured 210 tokens; this excerpt measures 257 with `metric/tokenizer.py`.
