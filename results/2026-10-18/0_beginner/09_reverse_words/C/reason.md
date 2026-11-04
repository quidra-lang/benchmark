# Task B selection: 09_reverse_words / C

## Answer requirements

Trace how the final word begins both reversals, including the difference in character and space handling.

## Evidence and answer

The sentence and its length drive backward byte traversal (all characters are ASCII), so line starts the first output as enil and original space positions are mirrored. The first newline ends that output before strtok mutates the buffer. strtok splits on spaces, the assignment records each word pointer and increments count, then the reverse index traversal prints line unchanged and writes one space before each later word. The declaration of the pointer-array capacity does not affect either traversal or space placement.

## Minimization

Selected complete lines of `main.c`: 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18. The excerpt preserves their text, indentation and order.

Adding the omitted storage declaration gives the array capacity, which does not change the iteration or formatting for this sentence. The previous excerpt contained 252 tokens; the selected excerpt contains **242 tokens** using `metric/tokenizer.py`.
