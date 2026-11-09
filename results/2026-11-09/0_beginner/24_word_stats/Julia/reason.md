# Task B: 24_word_stats / Julia

The numerator is the exact total count of word characters, and the denominator is the exact word count; the quotient is an average measured in characters per word. In a truncating port, convert at least one operand to a real value at this division (or choose a real-division operator) while keeping the stored counts integral. Formatting to two decimals is later and cannot repair a truncated quotient.

sum(length,words) and length(words) are Int counts; / already returns a real quotient for these operands, unlike div.

Evidence is from `main.jl`, L7,L8.

- L7: `total = sum(length, words)`
- L8: `@printf("average length: %.2f\n", total / length(words))`

Minimization: The word collection/count definitions, total and division expression are sufficient to identify both operands and existing real semantics. Unrelated reporting fields on the same complete line remain unavoidable. The selected complete original lines, in source order, cost 39 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 39, and the complete source costs 128. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
