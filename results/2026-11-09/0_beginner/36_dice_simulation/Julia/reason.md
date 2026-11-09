# Task B: 36_dice_simulation / Julia

Seed 12345 advances by state=(48271×state) mod 2147483647 twice per trial. The first states are 595905495 and 1558181227, mapped by state mod 6 +1 to dice 4 and 2, hence sum 6. Exactly 1000 trials contribute one count each to eleven reported sum buckets 2..12 within thirteen initially zero storage slots. Output prints those eleven buckets in ascending sum order, then a twelfth line for the first maximum-frequency bucket, so a tie favors the smaller sum.

Int state arithmetic stays within its range for this generator. counts[sum+1] translates logical sums 2..12 to one-based slots 3..13; argmax is first-on-tie.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14.

- L2: `state = 12345`
- L3: `counts = zeros(Int, 13)`
- L4: `for trial = 1:1000`
- L5: `state = (state * 48271) % 2147483647`
- L6: `first_die = state % 6 + 1`
- L7: `state = (state * 48271) % 2147483647`
- L8: `second_die = state % 6 + 1`
- L9: `counts[first_die+second_die+1] += 1`
- L10: `end`
- L11: `for total = 2:12`
- L12: `println(total, ": ", counts[total+1])`
- L13: `end`
- L14: `println("most frequent: ", argmax(counts[3:13])+1)`

Minimization: Seed, trial bound, both random updates, die mapping, zero initialization, bucket update and both output stages are necessary for this end-to-end simulation explanation. No list of all generated states is required. The selected complete original lines, in source order, cost 221 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 221, and the complete source costs 232. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
