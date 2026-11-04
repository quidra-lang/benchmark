# Task B selection: 13_diamond_pattern / Zig

## Answer requirements

Explain the transition from expansion to contraction and derive the spaces and stars on lines five and six of the size-five diamond.

## Evidence and answer

The loop begins at index 0, so output lines five and six use row=4 and row=5. The conditional maps them to i=5 and i=4. The standard I/O writer binding identifies splatByteAll as repeated-byte output for the two fields, then writeByte adds the newline.

With n=5 from the question, these lines use i=5 and i=4, giving 0 spaces and 9 asterisks, then 1 space and 7 asterisks. The separately declared n=5 repeats the given size. The traversal and row construction still establish the transition and one widest row.

## Minimization

Selected complete lines of `main.zig`: 5, 6, 8, 9, 10, 11, 12. The excerpt preserves their text, indentation and order.

Adding the size declaration would repeat a supplied fact. Removing the traversal instead would lose the connection between output line numbers and the internal row index. The previous excerpt contained 188 tokens; the selected excerpt contains **175 tokens** using `metric/tokenizer.py`.
