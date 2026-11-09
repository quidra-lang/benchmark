# Task B: 22_char_frequency / J

Remove the whole-sentence lowercase conversion. Count exact original-case letters using the ordered key sequence A..Z followed by a..z, emit only positive counts, and exclude every other character. In the supplied sentence uppercase P occurs twice and lowercase p seven times, replacing the current combined count 9. Existing per-key formatting remains suitable.

Keep the original sentence instead of tolower, extend the loop alphabet to uppercase then lowercase, and compare each exact letter to the original characters. The positive-count guard excludes unused letters.

Evidence is from `main.ijs`, L2,L3,L4,L5.

- L2: `sentence =. tolower 'Peter Piper picked a peck of pickled peppers!'`
- L3: `for_letter. 'abcdefghijklmnopqrstuvwxyz' do.`
- L4: `count =. +/letter=sentence`
- L5: `if. count>0 do. smoutput letter, ': ', ":count end.`

Minimization: The stored sentence, normalization, count-key/range construction, zero filtering and output are needed for the requested complete change. No per-character trace beyond the P/p count is necessary. The selected complete original lines, in source order, cost 75 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 75, and the complete source costs 95. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
