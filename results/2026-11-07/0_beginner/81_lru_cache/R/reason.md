# Task B: 81_lru_cache / R

Before the fourth B access, cache order is C,A,B. Finding B removes its old position and prepends it, yielding B,C,A and incrementing hits only. The following D is a miss: evict least-recent A, prepend D, yielding D,B,C and incrementing misses only. The next access reads this updated order. The access sequence is separately stored and does not share mutable ordering storage with the cache.

R subsets/concatenates and rebinds cache under value semantics; accesses is a separate vector. No shared reference object exposes cache reordering to the input sequence.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20.

- L1: `cache <- character(0)`
- L2: `hits <- 0`
- L3: `misses <- 0`
- L4: `for (key in c("B", "A", "C", "B", "D", "A", "B", "E", "A", "D", "D", "C", "A", "E", "B")) {`
- L5: `index <- match(key, cache)`
- L6: `if (!is.na(index)) {`
- L7: `hits <- hits + 1`
- L8: `cache <- cache[-index]`
- L9: `result <- "hit"`
- L10: `} else {`
- L11: `misses <- misses + 1`
- L12: `if (length(cache) == 3) {`
- L13: `result <- paste("miss, evict", tail(cache, 1))`
- L14: `cache <- head(cache, -1)`
- L15: `} else {`
- L16: `result <- "miss"`
- L17: `}`
- L18: `}`
- L19: `cache <- c(key, cache)`
- L20: `cat(sprintf("%s: %s [%s]\n", key, result, paste(cache, collapse = " ")))`

Minimization: The initial input/cache/counters, membership branch, refresh/eviction update and status output are necessary for this one access operation. Final aggregate reporting is unnecessary. The selected complete original lines, in source order, cost 320 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 320, and the complete source costs 350. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
