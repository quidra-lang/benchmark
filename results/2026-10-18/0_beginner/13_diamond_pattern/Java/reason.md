# Task B selection: 13_diamond_pattern / Java

## Answer requirements

Explain the transition from expansion to contraction and derive the spaces and stars on lines five and six of the size-five diamond.

## Evidence and answer

The loop starts at row 1; the conditional reflects i after row n. The two repeat calls append n-i spaces and 2*i-1 asterisks, then println ends the row.

With n=5 from the question, these lines use i=5 and i=4, giving 0 spaces and 9 asterisks, then 1 space and 7 asterisks. The separately declared n=5 repeats the given size. The traversal and row construction still establish the transition and one widest row.

## Minimization

Selected complete lines of `Main.java`: 4, 5, 6. The excerpt preserves their text, indentation and order.

Adding the size declaration would repeat a supplied fact. Removing the traversal instead would lose the connection between output line numbers and the internal row index. The previous excerpt contained 121 tokens; the selected excerpt contains **110 tokens** using `metric/tokenizer.py`.
