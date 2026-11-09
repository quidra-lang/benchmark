# Task B: 21_remove_duplicates / J

The fifteen stored values retain their first-appearance order. The three 12s occur at zero-based positions 0,2,13 (one-based 1,3,14): the first is retained and the later two are duplicates. The full retained sequence is `12 5 8 3 20 15 7 9`, eight values, so 15-8=7 are removed. The two lines are `12 5 8 3 20 15 7 9` and `removed: 7`.

~. preserves the first occurrence of each equal numeric value. #values-#unique supplies the removed count; joining/formatting supplies the two lines.

Evidence is from `main.ijs`, L1,L2,L3,L4.

- L1: `values =: 12 5 12 8 3 5 20 8 8 15 3 7 20 12 9`
- L2: `unique =: ~.values`
- L3: `smoutput ":unique`
- L4: `smoutput 'removed: ', ": (#values)-#unique`

Minimization: All four substantive lines are needed for this short end-to-end program: input, ordered duplicate removal, retained output and removed count. This is a direct dependency selection, not a full-source fallback. The selected complete original lines, in source order, cost 73 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 73, and the complete source costs 73. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
