# Task B: 12_grade_letters / R

The present initialization already supplies zero counts for the absent D grade. Before a reused second report, reset the entire count storage to those zeros (or rebuild its frequency result) before processing scores again; otherwise additive updates would double existing counts. A score increases its own grade slot once, and the D read stays zero because no score selects D.

cut(...,labels=rev(grades)) retains all grade levels, including D, and table(assigned) computes a fresh table containing zero for unused levels. Recomputing table already resets it rather than adding into the old table.

Evidence is from `main.R`, L2,L3,L5,L6.

- L2: `grades <- c("A", "B", "C", "D", "F")`
- L3: `assigned <- cut(scores, c(-Inf, 60, 70, 80, 90, Inf), labels = rev(grades), right = FALSE)`
- L5: `counts <- table(assigned)`
- L6: `cat(sprintf("%s: %d\n", grades, counts[grades]), sep = "")`

Minimization: The grade labels, zero/default construction, one update or fresh frequency construction, and final per-grade read are needed. The literal score list is unnecessary because the question specifies the same scores and the absent D. The selected complete original lines, in source order, cost 125 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 155, and the complete source costs 202. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
