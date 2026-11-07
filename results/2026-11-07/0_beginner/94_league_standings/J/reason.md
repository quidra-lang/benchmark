# Task B: 94_league_standings / J

The standings order must have its own ordering storage if the original sequence must remain available. Sharing unchanged team records between those two order containers is safe; sharing/reordering the container itself loses the original sequence. Inspect the sort operation rather than recomputing statistics.

The standings grade expression returns a separate index order, leaving names intact; however names was already alphabetically sorted at initialization, so preserve a separate raw name sequence before that earlier sort if original means registration/source order.

Evidence is from `main.ijs`, L6,L40.

- L6: `names =. /:~;:'Lions Tigers Eagles Sharks Wolves Bears'`
- L40: `order =. \:points,.difference,.goalsfor`

Minimization: The original ordering binding and actual standings sort are sufficient to distinguish order storage from record sharing. Score updates and table rendering are outside this expression-level question. The selected complete original lines, in source order, cost 34 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 611, and the complete source costs 844. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
