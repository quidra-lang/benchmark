# Task B: 87_gaussian_elimination / J

Capture factor=2/4=0.5 before overwriting the next row's column-1 entry. Every later column update in that row must reuse the captured factor. Recomputing it after column 1 has been reduced to zero would give 0 instead and incorrectly leave later entries unchanged.

factor reads the two column entries before the for_j. loop amends any of them; every amended value uses that factor binding.

Evidence is from `main.ijs`, L17,L18,L19,L20.

- L17: `factor =. ((<i,k){a)%(<k,k){a`
- L18: `for_j. k+i.(n+1)-k do.`
- L19: `value =. ((<i,j){a)-factor*(<k,j){a`
- L20: `a =. value (<i,j)}a`

Minimization: Only the factor read and following entry-update loop are needed. The pivot search/swap and full matrices are already fixed by the question and do not change this read-before-write dependency. The selected complete original lines, in source order, cost 93 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 93, and the complete source costs 599. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
