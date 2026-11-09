# Task B: 12_grade_letters / J

The present initialization already supplies zero counts for the absent D grade. Before a reused second report, reset the entire count storage to those zeros (or rebuild its frequency result) before processing scores again; otherwise additive updates would double existing counts. A score increases its own grade slot once, and the D read stays zero because no score selects D.

counts is initialized as five zeros in the same order as grades, then an indexed slot is incremented. Reexecute that initialization before reuse; the output reads every slot including D.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L9,L10.

- L2: `grades =. 'ABCDF'`
- L3: `counts =. 5$0`
- L4: `for_score. 78 90 100 59 80 85 89 70 45 93 do.`
- L5: `index =. +/ score < 90 80 70 60`
- L6: `counts =. (>:index{counts) index}counts`
- L7: `smoutput (":score), ': ', index{grades`
- L9: `for_index. i.5 do.`
- L10: `smoutput (index{grades), ': ', ":index{counts`

Minimization: The grade labels, zero/default construction, one update or fresh frequency construction, and final per-grade read are needed. The literal score list is unnecessary because the question specifies the same scores and the absent D. The selected complete original lines, in source order, cost 150 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 153, and the complete source costs 173. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
