# Task B: 46_word_frequency / J

The first normalized cat contributes one occurrence and the second contributes another to the same exact word key, yielding count 2. The actual source may aggregate those occurrences directly instead of exposing a sequential missing-key mutation; the counting mechanism must be read as written.

~.tokens obtains unique word keys and the word/token equality matrix followed by +/ computes each complete frequency. For cat, no match contributes zero and its two matches sum to 2; there is no mutable map entry to initialize.

Evidence is from `main.ijs`, L4,L5,L6.

- L4: `tokens =. ;:text`
- L5: `words =. /:~ ~.tokens`
- L6: `counts =. +/"1 words =/ tokens`

Minimization: The exact key/count construction is sufficient. Normalization is already granted in the question, and ranking/output do not affect this local count update. The selected complete original lines, in source order, cost 36 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 36, and the complete source costs 249. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
