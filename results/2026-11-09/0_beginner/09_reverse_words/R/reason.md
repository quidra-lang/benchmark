# Task B: 09_reverse_words / R

The first reversal acts on the character sequence: the final word line becomes enil and its preceding space moves after those reversed letters. The second first splits on spaces, reverses the sequence of whole word tokens, and joins them with single spaces. Its first token is therefore line, with the four letters still in their original order.

rev(characters) reverses single-character tokens; rev(words) reverses space-split whole words. Distinct paste collapse separators reconstruct the two outputs.

Evidence is from `main.R`, L1,L2,L3,L4,L5.

- L1: `sentence <- "every program starts with a single line"`
- L2: `characters <- strsplit(sentence, "", fixed = TRUE)[[1]]`
- L3: `words <- strsplit(sentence, " ", fixed = TRUE)[[1]]`
- L4: `cat(paste(rev(characters), collapse = ""), "\n", sep = "")`
- L5: `cat(paste(rev(words), collapse = " "), "\n", sep = "")`

Minimization: The shared input and the two neighboring reverse/rejoin operations establish the unit of reversal. No per-character trace or unrelated input is needed. The selected complete original lines, in source order, cost 134 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 134, and the complete source costs 134. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
