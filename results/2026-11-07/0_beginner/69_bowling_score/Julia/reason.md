# Task B: 69_bowling_score / Julia

The present inputs are numeric pin-count literals, so their entry point performs no string-to-number conversion. If a roll arrives as decimal text `"10"`, normalize it exactly once when ingesting that token into the rolls sequence, before existing comparison/addition. The resulting numeric value is 10; frame rules remain unchanged.

Use parse(Int,token) before inserting into the numeric rolls vector; the current for rolls in games loop receives already numeric vectors.

Evidence is from `main.jl`, L3,L9,L13.

- L3: `[8, 1, 10, 7, 3, 9, 0, 10, 10, 2, 6, 6, 4, 0, 9, 10, 7, 2],`
- L9: `for (number, rolls) in enumerate(games)`
- L13: `if rolls[position] == 10`

Minimization: One representative numeric initializer, the ingestion binding and first numeric use establish the missing conversion boundary. The full scoring routine is unnecessary for one roll normalization. The selected complete original lines, in source order, cost 94 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 374, and the complete source costs 596. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
