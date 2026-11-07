# Task B selection: 13_diamond_pattern / C++

## Answer requirements

Explain the transition from expansion to contraction and derive the spaces and stars on lines five and six of the size-five diamond.

## Evidence and answer

row begins at 1; the conditional changes i from row to 2*n-row after row n. The two std::string constructors emit n-i spaces and 2*i-1 asterisks, followed by a newline.

With n=5 from the question, these lines use i=5 and i=4, giving 0 spaces and 9 asterisks, then 1 space and 7 asterisks. The separately declared n=5 repeats the given size. The traversal and row construction still establish the transition and one widest row.

## Minimization

Selected complete lines of `main.cpp`: 6, 7, 8. The excerpt preserves their text, indentation and order.

Adding the size declaration would repeat a supplied fact. Removing the traversal instead would lose the connection between output line numbers and the internal row index. The previous excerpt contained 125 tokens; the selected excerpt contains **115 tokens** using `metric/tokenizer.py`.

## Current token measurement

Task A: **152 tokens**. Task B: **115 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
