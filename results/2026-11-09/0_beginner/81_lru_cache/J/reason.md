# Task B: 81_lru_cache / J

Before the fourth B access, cache order is C,A,B. Finding B removes its old position and prepends it, yielding B,C,A and incrementing hits only. The following D is a miss: evict least-recent A, prepend D, yielding D,B,C and incrementing misses only. The next access reads this updated order. The access sequence is separately stored and does not share mutable ordering storage with the cache.

J removes/rebuilds/rebinds cache values; status and hit/miss counters are updated in the same access block. The input sequence remains a different value.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17.

- L2: `cache =. ''`
- L3: `hits =. misses =. 0`
- L4: `for_key. 'BACBDABEADDCAEB' do.`
- L5: `status =. 'hit'`
- L6: `if. key e.cache do. hits =. >:hits`
- L7: `else.`
- L8: `misses =. >:misses`
- L9: `status =. 'miss'`
- L10: `if. 3=#cache do.`
- L11: `status =. status,', evict ',{:cache`
- L12: `cache =. }:cache`
- L13: `end.`
- L14: `end.`
- L15: `cache =. key,cache-.key`
- L16: `contents =. }. ; (<' ') ,&.> <"0 cache`
- L17: `smoutput key,': ',status,' [',contents,']'`

Minimization: The initial input/cache/counters, membership branch, refresh/eviction update and status output are necessary for this one access operation. Final aggregate reporting is unnecessary. The selected complete original lines, in source order, cost 184 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 184, and the complete source costs 230. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
