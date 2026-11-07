# Task B: 69_bowling_score / R

The present inputs are numeric pin-count literals, so their entry point performs no string-to-number conversion. If a roll arrives as decimal text `"10"`, normalize it exactly once when ingesting that token into the rolls sequence, before existing comparison/addition. The resulting numeric value is 10; frame rules remain unchanged.

Use as.integer(token) before storing/using the roll; current game vectors contain numeric values and have no parse operation at that entry point.

Evidence is from `main.R`, L2,L9,L14.

- L2: `c(8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2),`
- L9: `rolls <- games[[number]]`
- L14: `if (rolls[position] == 10) {`

Minimization: One representative numeric initializer, the ingestion binding and first numeric use establish the missing conversion boundary. The full scoring routine is unnecessary for one roll normalization. The selected complete original lines, in source order, cost 89 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 348, and the complete source costs 600. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
