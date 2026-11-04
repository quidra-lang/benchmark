# Task B selection: 13_diamond_pattern / Python

## Answer requirements

Explain the transition from expansion to contraction and derive the spaces and stars on lines five and six of the size-five diamond.

## Evidence and answer

The unpacked ranges first enumerate 1 through n, then n-1 down to 1, so the widest row is not repeated. String multiplication uses n-i for spaces and 2*i-1 for asterisks, and print adds a newline.

With n=5 from the question, these lines use i=5 and i=4, giving 0 spaces and 9 asterisks, then 1 space and 7 asterisks. The separately declared n=5 repeats the given size. The traversal and row construction still establish the transition and one widest row.

## Minimization

Selected complete lines of `main.py`: 2, 3. The excerpt preserves their text, indentation and order.

Adding the size declaration would repeat a supplied fact. Removing the traversal instead would lose the connection between output line numbers and the internal row index. The previous excerpt contained 83 tokens; the selected excerpt contains **77 tokens** using `metric/tokenizer.py`.
