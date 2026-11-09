# Task B: 12_grade_letters / Julia

The present initialization already supplies zero counts for the absent D grade. Before a reused second report, reset the entire count storage to those zeros (or rebuild its frequency result) before processing scores again; otherwise additive updates would double existing counts. A score increases its own grade slot once, and the D read stays zero because no score selects D.

zeros(Int,5) creates fresh zeroed storage; counts[index] += 1 mutates one slot. Reinitialize it before a second report, and zip prints the zero D entry.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L9,L10.

- L2: `grades = ["A", "B", "C", "D", "F"]`
- L3: `counts = zeros(Int, 5)`
- L4: `for score in [78, 90, 100, 59, 80, 85, 89, 70, 45, 93]`
- L5: `index = score >= 90 ? 1 : score >= 80 ? 2 : score >= 70 ? 3 : score >= 60 ? 4 : 5`
- L6: `counts[index] += 1`
- L7: `println(score, ": ", grades[index])`
- L9: `for (grade, total) in zip(grades, counts)`
- L10: `println(grade, ": ", total)`

Minimization: The grade labels, zero/default construction, one update or fresh frequency construction, and final per-grade read are needed. The literal score list is unnecessary because the question specifies the same scores and the absent D. The selected complete original lines, in source order, cost 219 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 222, and the complete source costs 236. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
