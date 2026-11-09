# Task B: 83_topological_sort / R

Eligible candidates must be untaken and have zero remaining indegree. For the described list-2 stopping state, no eligible candidate exists even though some courses remain untaken. The empty/none check breaks before reading/removing a candidate, so it never pops an empty collection. The remaining names are obtained in alphabetical order and feed the cycle line after its `cycle: ` label. If all courses were taken, the same stop condition would have an empty remaining list instead.

ready is formed from alphabetically sorted courses; !length(ready) breaks before ready[1], and the returned set difference feeds the cycle line.

Evidence is from `main.R`, L9,L10,L11,L12,L13,L17,L32,L35.

- L9: `alphabetical <- sort(courses, method = "radix")`
- L10: `repeat {`
- L11: `ready <- alphabetical[!alphabetical %in% ordered & indegree[alphabetical] == 0]`
- L12: `if (length(ready) == 0) break`
- L13: `course <- ready[1]`
- L17: `list(order = ordered, remaining = alphabetical[!alphabetical %in% ordered])`
- L32: `second <- topological(courses2, edges2)`
- L35: `cat("cycle: ", paste(second$remaining, collapse = " "), "\n", sep = "")`

Minimization: The local alphabetic order, eligibility condition, empty guard/read order and remaining-data output establish this stopping edge. The whole indegree-building routine is unnecessary to explain this already reached local state. The selected complete original lines, in source order, cost 153 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 596, and the complete source costs 741. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
