# Task B selection: 13_diamond_pattern / Lua

## Answer requirements

Explain the transition from expansion to contraction and derive the spaces and stars on lines five and six of the size-five diamond.

## Evidence and answer

The first loop calls row(i) from 1 through n, and the second starts at n-1 and steps downward, so n is used only once. The helper’s repeated spaces and stars precede its newline; keeping its end shows the traversal is outside that helper.

With n=5 from the question, these lines use i=5 and i=4, giving 0 spaces and 9 asterisks, then 1 space and 7 asterisks. The separately declared n=5 repeats the given size. The traversal and row construction still establish the transition and one widest row.

## Minimization

Selected complete lines of `main.lua`: 3, 4, 5, 7, 8. The excerpt preserves their text, indentation and order.

Adding the size declaration would repeat a supplied fact. Removing the traversal instead would lose the connection between output line numbers and the internal row index. The previous excerpt contained 116 tokens; the selected excerpt contains **108 tokens** using `metric/tokenizer.py`.
