# Task B: 40_binary_search / R

Initial low/high are zero-based 0 and 15, so floor((0+15)/2)=7. This is a recorded position, while the corresponding array element is 31 at one-based ordinal 8. The probe list stores midpoint itself, not the fetched value; later comparisons are outside the requested first-midpoint analysis.

The algorithm records midpoint but reads numbers[midpoint+1] because R vectors are one-indexed.

Evidence is from `main.R`, L1,L3,L4,L8,L9,L10.

- L1: `numbers <- c(3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77)`
- L3: `lo <- 0`
- L4: `hi <- length(numbers) - 1`
- L8: `mid <- (lo + hi) %/% 2`
- L9: `probes <- c(probes, mid)`
- L10: `if (numbers[mid + 1] == target) {`

Minimization: The array, initial endpoints, midpoint computation, probe append and first array read establish both representations. Later branch updates and output are omitted. The selected complete original lines, in source order, cost 139 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 204, and the complete source costs 360. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
