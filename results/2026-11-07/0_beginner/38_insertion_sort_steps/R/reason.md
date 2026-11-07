# Task B: 38_insertion_sort_steps / R

The per-step counter starts at zero. Moving an already stored 52 one position right performs one increment; the final assignment of the extracted 17 into the vacated position is outside that incrementing block and adds none. Thus the shift count for this step is 1, measured in existing elements moved right, not all assignments.

shifts <- shifts+1 is inside the movement loop; the final numbers[j+1] <- value lies after its closing brace.

Evidence is from `main.R`, L6,L7,L8,L9,L10,L11,L12.

- L6: `shifts <- 0`
- L7: `while (j >= 1 && numbers[j] > value) {`
- L8: `numbers[j + 1] <- numbers[j]`
- L9: `shifts <- shifts + 1`
- L10: `j <- j - 1`
- L11: `}`
- L12: `numbers[j + 1] <- value`

Minimization: The zero initialization, movement-loop boundary, counter increment and final write are needed to distinguish the two assignment units. The whole insertion sort and unrelated passes are omitted. The selected complete original lines, in source order, cost 87 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 87, and the complete source costs 248. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
