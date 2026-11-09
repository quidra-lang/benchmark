# Task B: 96_poker_hand_rank / J

The rank alphabet encodes T as 10 and A as 14. Ordinary ace-high comparison retains 14. The special wheel condition recognizes exactly the distinct ranks {2,3,4,5,14}; only then the comparison sequence becomes [5,4,3,2,1], treating ace as low 1. These rank values are internal card-comparison data, not the final hand's printed ordinal position.

Alphabet lookup plus 2 establishes numeric ranks; the wheel predicate and sequence branch replace only that special comparison vector.

Evidence is from `main.ijs`, L11,L12,L16,L17,L18,L31,L32,L33,L34,L35.

- L11: `rank =. 2+'23456789TJQKA'i.{.card`
- L12: `counts =. (>:rank{counts) rank}counts`
- L16: `distinct =. I.counts>0`
- L17: `wheel =. distinct-:2 3 4 5 14`
- L18: `straight =. (5=#distinct)*.((4=({:distinct)-{.distinct)+.wheel)`
- L31: `sequence =. i.0`
- L32: `if. straight*.wheel do. sequence =. 5 4 3 2 1`
- L33: `else.`
- L34: `sequence =. |.distinct`
- L35: `sequence =. sequence {~ \:sequence{counts`

Minimization: Rank conversion, distinct/wheel predicate and comparison-sequence choice suffice. Full category ranking and hand-output numbering are intentionally omitted. The selected complete original lines, in source order, cost 151 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 328, and the complete source costs 742. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
