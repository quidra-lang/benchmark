# Task B: 46_word_frequency / Julia

The first normalized cat contributes one occurrence and the second contributes another to the same exact word key, yielding count 2. The actual source may aggregate those occurrences directly instead of exposing a sequential missing-key mutation; the counting mechanism must be read as written.

frequencies[word]=get(frequencies,word,0)+1 uses default 0 on the first lookup, stores 1, then reads 1 and stores 2 for the second cat. The Dict mutates; its Int values are replaced.

Evidence is from `main.jl`, L3,L5,L6.

- L3: `frequencies = Dict{String,Int}()`
- L5: `word = String(match.match)`
- L6: `frequencies[word] = get(frequencies, word, 0)+1`

Minimization: The exact key/count construction is sufficient. Normalization is already granted in the question, and ranking/output do not affect this local count update. The selected complete original lines, in source order, cost 48 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 74, and the complete source costs 289. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
