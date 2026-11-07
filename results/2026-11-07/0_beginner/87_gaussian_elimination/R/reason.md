# Task B: 87_gaussian_elimination / R

Capture factor=2/4=0.5 before overwriting the next row's column-1 entry. Every later column update in that row must reuse the captured factor. Recomputing it after column 1 has been reduced to zero would give 0 instead and incorrectly leave later entries unchanged.

factor <- values[i,k]/values[k,k] precedes the loop; the indexed replacement expression uses that stored value for every j.

Evidence is from `main.R`, L8,L9,L10.

- L8: `factor <- values[i, k] / values[k, k]`
- L9: `for (j in k:(n + 1)) {`
- L10: `values[i, j] <- values[i, j] - factor * values[k, j]`

Minimization: Only the factor read and following entry-update loop are needed. The pivot search/swap and full matrices are already fixed by the question and do not change this read-before-write dependency. The selected complete original lines, in source order, cost 81 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 81, and the complete source costs 628. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
