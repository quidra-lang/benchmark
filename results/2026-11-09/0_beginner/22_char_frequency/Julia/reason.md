# Task B: 22_char_frequency / Julia

Remove the whole-sentence lowercase conversion. Count exact original-case letters using the ordered key sequence A..Z followed by a..z, emit only positive counts, and exclude every other character. In the supplied sentence uppercase P occurs twice and lowercase p seven times, replacing the current combined count 9. Existing per-key formatting remains suitable.

Keep the original sentence instead of lowercase and traverse the two letter ranges in the requested order. count(==(letter),sentence) then distinguishes P and p.

Evidence is from `main.jl`, L1,L2,L3,L4.

- L1: `sentence = lowercase("Peter Piper picked a peck of pickled peppers!")`
- L2: `for letter = 'a':'z'`
- L3: `occurrences = count(==(letter), sentence)`
- L4: `occurrences > 0 && println(letter, ": ", occurrences)`

Minimization: The stored sentence, normalization, count-key/range construction, zero filtering and output are needed for the requested complete change. No per-character trace beyond the P/p count is necessary. The selected complete original lines, in source order, cost 79 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 79, and the complete source costs 81. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
