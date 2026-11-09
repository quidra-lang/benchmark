# Task B: 81_lru_cache / Julia

Before the fourth B access, cache order is C,A,B. Finding B removes its old position and prepends it, yielding B,C,A and incrementing hits only. The following D is a miss: evict least-recent A, prepend D, yielding D,B,C and incrementing misses only. The next access reads this updated order. The access sequence is separately stored and does not share mutable ordering storage with the cache.

Julia deleteat!/pop!/pushfirst! mutate the cache vector, while the distinct accesses vector is only traversed. The next iteration sees the same mutated cache object.

Evidence is from `main.jl`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15.

- L2: `cache = Char[]`
- L3: `hits, misses = 0, 0`
- L4: `for key in ['B', 'A', 'C', 'B', 'D', 'A', 'B', 'E', 'A', 'D', 'D', 'C', 'A', 'E', 'B']`
- L5: `index = findfirst(==(key), cache)`
- L6: `if index !== nothing`
- L7: `hits += 1`
- L8: `deleteat!(cache, index)`
- L9: `result = "hit"`
- L10: `else`
- L11: `misses += 1`
- L12: `result = length(cache) == 3 ? string("miss, evict ", pop!(cache)) : "miss"`
- L13: `end`
- L14: `pushfirst!(cache, key)`
- L15: `println(key, ": ", result, " [", join(cache, " "), "]")`

Minimization: The initial input/cache/counters, membership branch, refresh/eviction update and status output are necessary for this one access operation. Final aggregate reporting is unnecessary. The selected complete original lines, in source order, cost 271 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 271, and the complete source costs 309. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
