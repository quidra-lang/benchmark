# Task B: 36_dice_simulation / R

Seed 12345 advances by state=(48271×state) mod 2147483647 twice per trial. The first states are 595905495 and 1558181227, mapped by state mod 6 +1 to dice 4 and 2, hence sum 6. Exactly 1000 trials contribute one count each to eleven reported sum buckets 2..12 within thirteen initially zero storage slots. Output prints those eleven buckets in ascending sum order, then a twelfth line for the first maximum-frequency bucket, so a tie favors the smaller sum.

The numeric state products stay below exact-double integer limits. counts[sum+1] maps logical sums to one-based slots 3..13; which.max selects the first maximum.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12.

- L1: `state <- 12345`
- L2: `counts <- integer(13)`
- L3: `for (trial in 1:1000) {`
- L4: `state <- (state * 48271) %% 2147483647`
- L5: `first_die <- state %% 6 + 1`
- L6: `state <- (state * 48271) %% 2147483647`
- L7: `second_die <- state %% 6 + 1`
- L8: `index <- first_die + second_die + 1`
- L9: `counts[index] <- counts[index] + 1L`
- L10: `}`
- L11: `for (total in 2:12) cat(sprintf("%d: %d\n", total, counts[total + 1]))`
- L12: `cat(sprintf("most frequent: %d\n", which.max(counts[3:13]) + 1))`

Minimization: Seed, trial bound, both random updates, die mapping, zero initialization, bucket update and both output stages are necessary for this end-to-end simulation explanation. No list of all generated states is required. The selected complete original lines, in source order, cost 248 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 248, and the complete source costs 248. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
