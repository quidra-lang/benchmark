# Task B: 24_word_stats / J

The numerator is the exact total count of word characters, and the denominator is the exact word count; the quotient is an average measured in characters per word. In a truncating port, convert at least one operand to a real value at this division (or choose a real-division operator) while keeping the stored counts integral. Formatting to two decimals is later and cannot repair a truncated quotient.

The named total is +/#&>words and the denominator is #words. J % already supplies a real/rational quotient, so no conversion is needed here.

Evidence is from `main.ijs`, L2,L6,L7.

- L2: `lengths =: #&>words`
- L6: `total =: +/lengths`
- L7: `smoutput 'average length: ', , '2' 8!:2 total%#words`

Minimization: The word collection/count definitions, total and division expression are sufficient to identify both operands and existing real semantics. Unrelated reporting fields on the same complete line remain unavoidable. The selected complete original lines, in source order, cost 43 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 101, and the complete source costs 132. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
