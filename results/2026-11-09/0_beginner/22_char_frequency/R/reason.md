# Task B: 22_char_frequency / R

Remove the whole-sentence lowercase conversion. Count exact original-case letters using the ordered key sequence A..Z followed by a..z, emit only positive counts, and exclude every other character. In the supplied sentence uppercase P occurs twice and lowercase p seven times, replacing the current combined count 9. Existing per-key formatting remains suitable.

Remove tolower before utf8ToInt; map both ASCII ranges into ordered bins (or use explicit ordered keys), rather than the current 26 lowercase bins. Nonletter code points remain outside those ranges.

Evidence is from `main.R`, L1,L2,L3,L4.

- L1: `codes <- utf8ToInt(tolower("Peter Piper picked a peck of pickled peppers!"))`
- L2: `counts <- tabulate(codes - 96, nbins = 26)`
- L3: `present <- which(counts > 0)`
- L4: `cat(sprintf("%s: %d\n", letters[present], counts[present]), sep = "")`

Minimization: The stored sentence, normalization, count-key/range construction, zero filtering and output are needed for the requested complete change. No per-character trace beyond the P/p count is necessary. The selected complete original lines, in source order, cost 102 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 102, and the complete source costs 102. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
