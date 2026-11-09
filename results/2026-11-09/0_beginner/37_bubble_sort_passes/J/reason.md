# Task B: 37_bubble_sort_passes / J

Each pass compares adjacent elements only within the shrinking unsorted prefix, swapping precisely when the left value is greater. In pass 1, 88 moves right past 41,5,72,36 into the final slot. Pass lines are emitted after comparisons, before the no-swap early-stop test. The final array is `5 13 27 36 41 64 72 88`; the final printed pass is 6 (no swaps), and total swaps are 14. Per-pass swaps are 5,4,2,2,1,0.

changed resets each pass and is set only inside the swapping branch; total increments once for each adjacent swap, not each comparison.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17.

- L2: `values =. 27 64 13 88 41 5 72 36`
- L3: `swaps =. 0`
- L4: `for_pass. >:i.7 do.`
- L5: `changed =. 0`
- L6: `for_j. i.8-pass do.`
- L7: `if. (j{values) > (j+1){values do.`
- L8: `indices =. j,j+1`
- L9: `values =. (|.indices{values) indices}values`
- L10: `swaps =. >:swaps`
- L11: `changed =. 1`
- L12: `end.`
- L13: `end.`
- L14: `smoutput 'pass ',(":pass),': ',":values`
- L15: `if. -.changed do. break. end.`
- L16: `end.`
- L17: `smoutput 'swaps: ',":swaps`

Minimization: Input, both loop bounds, comparison/swap, counters, pass output and termination are all needed to derive the requested final pass and swap total. Main wrappers carry no additional sort behavior. The selected complete original lines, in source order, cost 193 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 193, and the complete source costs 210. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
