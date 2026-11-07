# Task B: 38_insertion_sort_steps / J

The per-step counter starts at zero. Moving an already stored 52 one position right performs one increment; the final assignment of the extracted 17 into the vacated position is outside that incrementing block and adds none. Thus the shift count for this step is 1, measured in existing elements moved right, not all assignments.

The shift increment follows the array right-shift inside while; the final indexed write occurs after end.

Evidence is from `main.ijs`, L7,L8,L9,L10,L11,L12,L13,L14.

- L7: `shifts =. 0`
- L8: `while. j>:0 do.`
- L9: `if. (j{values)<:value do. break. end.`
- L10: `values =. (j{values) (j+1)}values`
- L11: `j =. j-1`
- L12: `shifts =. >:shifts`
- L13: `end.`
- L14: `values =. value (j+1)}values`

Minimization: The zero initialization, movement-loop boundary, counter increment and final write are needed to distinguish the two assignment units. The whole insertion sort and unrelated passes are omitted. The selected complete original lines, in source order, cost 91 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 91, and the complete source costs 235. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
