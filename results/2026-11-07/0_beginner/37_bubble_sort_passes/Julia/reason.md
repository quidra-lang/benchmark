# Task B: 37_bubble_sort_passes / Julia

Each pass compares adjacent elements only within the shrinking unsorted prefix, swapping precisely when the left value is greater. In pass 1, 88 moves right past 41,5,72,36 into the final slot. Pass lines are emitted after comparisons, before the no-swap early-stop test. The final array is `5 13 27 36 41 64 72 88`; the final printed pass is 6 (no swaps), and total swaps are 14. Per-pass swaps are 5,4,2,2,1,0.

The j range 1:(8-pass) makes j+1 safe and omits the sorted suffix. The changed flag is checked only after println.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16.

- L2: `numbers = [27, 64, 13, 88, 41, 5, 72, 36]`
- L3: `total = 0`
- L4: `for pass = 1:7`
- L5: `changed = false`
- L6: `for j = 1:(8-pass)`
- L7: `if numbers[j] > numbers[j+1]`
- L8: `numbers[j], numbers[j+1] = numbers[j+1], numbers[j]`
- L9: `total += 1`
- L10: `changed = true`
- L11: `end`
- L12: `end`
- L13: `println("pass ", pass, ": ", join(numbers, " "))`
- L14: `!changed && break`
- L15: `end`
- L16: `println("swaps: ", total)`

Minimization: Input, both loop bounds, comparison/swap, counters, pass output and termination are all needed to derive the requested final pass and swap total. Main wrappers carry no additional sort behavior. The selected complete original lines, in source order, cost 214 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 214, and the complete source costs 225. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
