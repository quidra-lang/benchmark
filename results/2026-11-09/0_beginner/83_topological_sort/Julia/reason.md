# Task B: 83_topological_sort / Julia

Eligible candidates must be untaken and have zero remaining indegree. For the described list-2 stopping state, no eligible candidate exists even though some courses remain untaken. The empty/none check breaks before reading/removing a candidate, so it never pops an empty collection. The remaining names are obtained in alphabetical order and feed the cycle line after its `cycle: ` label. If all courses were taken, the same stop condition would have an empty remaining list instead.

findfirst returns nothing when no eligible course exists; the identity guard breaks before alphabetical[index], then setdiff(alphabetical,ordered) supplies sorted remaining.

Evidence is from `main.jl`, L10,L11,L12,L13,L14,L15,L22,L56,L59.

- L10: `alphabetical = sort(courses)`
- L11: `while true`
- L12: `index =`
- L13: `findfirst(course -> !(course in taken) && indegree[course] == 0, alphabetical)`
- L14: `index === nothing && break`
- L15: `course = alphabetical[index]`
- L22: `return ordered, setdiff(alphabetical, ordered)`
- L56: `order2, remaining = topological(courses2, edges2)`
- L59: `println("cycle: ", join(remaining, " "))`

Minimization: The local alphabetic order, eligibility condition, empty guard/read order and remaining-data output establish this stopping edge. The whole indegree-building routine is unnecessary to explain this already reached local state. The selected complete original lines, in source order, cost 126 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 544, and the complete source costs 656. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
