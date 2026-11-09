# Task B: 37_bubble_sort_passes / R

Each pass compares adjacent elements only within the shrinking unsorted prefix, swapping precisely when the left value is greater. In pass 1, 88 moves right past 41,5,72,36 into the final slot. Pass lines are emitted after comparisons, before the no-swap early-stop test. The final array is `5 13 27 36 41 64 72 88`; the final printed pass is 6 (no swaps), and total swaps are 14. Per-pass swaps are 5,4,2,2,1,0.

The colon ranges compare only adjacent valid positions; changed is reset, set by swaps and checked after cat.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15.

- L1: `numbers <- c(27, 64, 13, 88, 41, 5, 72, 36)`
- L2: `total <- 0`
- L3: `for (pass in 1:7) {`
- L4: `changed <- FALSE`
- L5: `for (j in 1:(8 - pass)) {`
- L6: `if (numbers[j] > numbers[j + 1]) {`
- L7: `numbers[c(j, j + 1)] <- numbers[c(j + 1, j)]`
- L8: `total <- total + 1`
- L9: `changed <- TRUE`
- L10: `}`
- L11: `}`
- L12: `cat(sprintf("pass %d: %s\n", pass, paste(numbers, collapse = " ")))`
- L13: `if (!changed) break`
- L14: `}`
- L15: `cat(sprintf("swaps: %d\n", total))`

Minimization: Input, both loop bounds, comparison/swap, counters, pass output and termination are all needed to derive the requested final pass and swap total. Main wrappers carry no additional sort behavior. The selected complete original lines, in source order, cost 236 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 236, and the complete source costs 236. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
