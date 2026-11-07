# Task B: 96_poker_hand_rank / Julia

The rank alphabet encodes T as 10 and A as 14. Ordinary ace-high comparison retains 14. The special wheel condition recognizes exactly the distinct ranks {2,3,4,5,14}; only then the comparison sequence becomes [5,4,3,2,1], treating ace as low 1. These rank values are internal card-comparison data, not the final hand's printed ordinal position.

findfirst in the rank alphabet plus 1 establishes ranks 2..14; sorted distinct equality identifies the wheel before its explicit low-ace sequence.

Evidence is from `main.jl`, L3,L4,L5,L6,L7,L8,L41,L42,L43.

- L3: `alphabet = "23456789TJQKA"`
- L4: `ranks = [findfirst(==(card[1]), alphabet)+1 for card in cards]`
- L5: `frequencies = [count(==(rank), ranks) for rank = 2:14]`
- L6: `distinct = [rank for rank = 2:14 if frequencies[rank-1] > 0]`
- L7: `wheel = distinct == [2, 3, 4, 5, 14]`
- L8: `straight = length(distinct) == 5 && (distinct[end]-distinct[1] == 4 || wheel)`
- L41: `sequence =`
- L42: `wheel && straight ? [5, 4, 3, 2, 1] :`
- L43: `sort(distinct; by = rank -> (-frequencies[rank-1], -rank))`

Minimization: Rank conversion, distinct/wheel predicate and comparison-sequence choice suffice. Full category ranking and hand-output numbering are intentionally omitted. The selected complete original lines, in source order, cost 235 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 557, and the complete source costs 865. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
