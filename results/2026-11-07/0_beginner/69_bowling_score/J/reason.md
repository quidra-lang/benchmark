# Task B: 69_bowling_score / J

The present inputs are numeric pin-count literals, so their entry point performs no string-to-number conversion. If a roll arrives as decimal text `"10"`, normalize it exactly once when ingesting that token into the rolls sequence, before existing comparison/addition. The resulting numeric value is 10; frame rules remain unchanged.

Use J decimal numeric parsing (0".) at token ingestion before rolls is consumed; current rolls are extracted from numeric game data and compared numerically.

Evidence is from `main.ijs`, L2,L4,L9.

- L2: `games =. (8 1 10 7 3 9 0 10 10 2 6 6 4 0 9 10 7 2);(3 4 5 2 7 1 0 6 8 1 4 4 2 3 6 2 9 0 1 5);(5 5 0 10 7 3 9 1 6 4 8 2 3 7 4 6 1 9 7 3 5);(12$10);(10 9 1 10 10 7 2 0 0 10 8 1 10 6 4 10)`
- L4: `rolls =. >game{games`
- L9: `elseif. 10=index{rolls do.`

Minimization: One representative numeric initializer, the ingestion binding and first numeric use establish the missing conversion boundary. The full scoring routine is unnecessary for one roll normalization. The selected complete original lines, in source order, cost 205 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 274, and the complete source costs 444. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
