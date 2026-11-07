# Task B: 83_topological_sort / J

Eligible candidates must be untaken and have zero remaining indegree. For the described list-2 stopping state, no eligible candidate exists even though some courses remain untaken. The empty/none check breaks before reading/removing a candidate, so it never pops an empty collection. The remaining names are obtained in alphabetical order and feed the cycle line after its `cycle: ` label. If all courses were taken, the same stop condition would have an empty remaining list instead.

The names are alphabetically sorted before the search. The available mask is checked for emptiness before its first index is selected; the final cycle line uses the still-untaken names.

Evidence is from `main.ijs`, L3,L13,L14,L15,L28.

- L3: `names =. /:~names`
- L13: `available =. I.(-.taken)*.indegree=0`
- L14: `if. 0=#available do. break. end.`
- L15: `selected =. {.available`
- L28: `if. showcycle do. smoutput 'cycle: ',}. ; (<' ') ,&.> (-.taken)#names end.`

Minimization: The local alphabetic order, eligibility condition, empty guard/read order and remaining-data output establish this stopping edge. The whole indegree-building routine is unnecessary to explain this already reached local state. The selected complete original lines, in source order, cost 85 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 304, and the complete source costs 541. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
