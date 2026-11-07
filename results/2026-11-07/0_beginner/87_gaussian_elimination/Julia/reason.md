# Task B: 87_gaussian_elimination / Julia

Capture factor=2/4=0.5 before overwriting the next row's column-1 entry. Every later column update in that row must reuse the captured factor. Recomputing it after column 1 has been reduced to zero would give 0 instead and incorrectly leave later entries unchanged.

factor=matrix[i,k]/matrix[k,k] precedes the column loop; each matrix[i,j]=matrix[i,j]-factor*matrix[k,j] reuses the same captured scalar.

Evidence is from `main.jl`, L11,L12,L13.

- L11: `factor = matrix[i, k]/matrix[k, k]`
- L12: `for j = k:(n+1)`
- L13: `matrix[i, j] = matrix[i, j]-factor*matrix[k, j]`

Minimization: Only the factor read and following entry-update loop are needed. The pivot search/swap and full matrices are already fixed by the question and do not change this read-before-write dependency. The selected complete original lines, in source order, cost 72 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 72, and the complete source costs 520. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
