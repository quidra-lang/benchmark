# Task B selection: 13_diamond_pattern / C#

## Answer requirements

Explain the transition from expansion to contraction and derive the spaces and stars on lines five and six of the size-five diamond.

## Evidence and answer

row begins at 1. The conditional changes i from row to 2*n-row after row n. The two string constructors repeat spaces and stars with the corresponding counts, and Console.WriteLine emits the row once. The detached loop braces add no transition or repetition evidence.

With n=5 from the question, these lines use i=5 and i=4, giving 0 spaces and 9 asterisks, then 1 space and 7 asterisks. The separately declared n=5 repeats the given size. The traversal and row construction still establish the transition and one widest row.

## Minimization

Selected complete lines of `Program.cs`: 4, 6, 7. The excerpt preserves their text, indentation and order.

Adding the size declaration would repeat a supplied fact. Removing the traversal instead would lose the connection between output line numbers and the internal row index. The previous excerpt contained 120 tokens; the selected excerpt contains **107 tokens** using `metric/tokenizer.py`.
