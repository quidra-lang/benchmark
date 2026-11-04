# Task B selection: 13_diamond_pattern / TypeScript

## Answer requirements

Explain the transition from expansion to contraction and derive the spaces and stars on lines five and six of the size-five diamond.

## Evidence and answer

The loop starts at row 1. The conditional takes i=row up to n and i=2*n-row afterward. The two repeat calls build the fields in order before a single console.log.

With n=5 from the question, these lines use i=5 and i=4, giving 0 spaces and 9 asterisks, then 1 space and 7 asterisks. The separately declared n=5 repeats the given size. The traversal and row construction still establish the transition and one widest row.

## Minimization

Selected complete lines of `main.ts`: 2, 3, 4. The excerpt preserves their text, indentation and order.

Adding the size declaration would repeat a supplied fact. Removing the traversal instead would lose the connection between output line numbers and the internal row index. The previous excerpt contained 111 tokens; the selected excerpt contains **102 tokens** using `metric/tokenizer.py`.
