# Task B: 24_word_stats / R

The numerator is the exact total count of word characters, and the denominator is the exact word count; the quotient is an average measured in characters per word. In a truncating port, convert at least one operand to a real value at this division (or choose a real-division operator) while keeping the stored counts integral. Formatting to two decimals is later and cannot repair a truncated quotient.

nchar and length supply exact small counts and sum(lengths) is total. The output uses total/length(words), and R / is already real division.

Evidence is from `main.R`, L2,L3,L4,L5,L6,L7.

- L2: `lengths <- nchar(words)`
- L3: `total <- sum(lengths)`
- L4: `cat(sprintf(`
- L5: `"words: %d\nlongest: %s\nshortest: %s\naverage length: %.2f\n",`
- L6: `length(words), words[which.max(lengths)], words[which.min(lengths)], total / length(words)`
- L7: `))`

Minimization: The word collection/count definitions, total and division expression are sufficient to identify both operands and existing real semantics. Unrelated reporting fields on the same complete line remain unavoidable. The selected complete original lines, in source order, cost 97 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 97, and the complete source costs 145. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
