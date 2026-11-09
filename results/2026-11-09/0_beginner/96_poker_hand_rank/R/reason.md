# Task B: 96_poker_hand_rank / R

The rank alphabet encodes T as 10 and A as 14. Ordinary ace-high comparison retains 14. The special wheel condition recognizes exactly the distinct ranks {2,3,4,5,14}; only then the comparison sequence becomes [5,4,3,2,1], treating ace as low 1. These rank values are internal card-comparison data, not the final hand's printed ordinal position.

match against the rank alphabet plus 1 establishes ranks; equality to c(2,3,4,5,14) selects c(5,4,3,2,1).

Evidence is from `main.R`, L3,L4,L5,L6,L7,L8,L30.

- L3: `alphabet <- strsplit("23456789TJQKA", "", fixed = TRUE)[[1]]`
- L4: `ranks <- match(substr(cards, 1, 1), alphabet) + 1`
- L5: `frequencies <- tabulate(ranks, nbins = 14)`
- L6: `distinct <- which(frequencies > 0)`
- L7: `wheel <- identical(distinct, c(2L, 3L, 4L, 5L, 14L))`
- L8: `straight <- length(distinct) == 5 && (max(distinct) - min(distinct) == 4 || wheel)`
- L30: `sequence <- if (wheel && straight) c(5, 4, 3, 2, 1) else distinct[order(-frequencies[distinct], -distinct)]`

Minimization: Rank conversion, distinct/wheel predicate and comparison-sequence choice suffice. Full category ranking and hand-output numbering are intentionally omitted. The selected complete original lines, in source order, cost 214 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 490, and the complete source costs 996. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
