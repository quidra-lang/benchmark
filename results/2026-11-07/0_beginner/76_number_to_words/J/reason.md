# Task B: 76_number_to_words / J

71000 becomes `seventy-one thousand`; 300019 becomes `three hundred thousand nineteen`; whole input 0 becomes `zero`. Below-one-thousand zero subparts return empty text and are omitted from composition, rather than injecting zero words. Tens/ones supply the hyphen in seventy-one, while nonempty thousand/remainder components are joined with single spaces.

The small helper handles hundreds and hyphenated tens; the whole-input branch treats zero separately, then joins only populated parts before naming words.

Evidence is from `main.ijs`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L16,L17,L18,L19,L20,L21.

- L1: `underthousand =: 3 : 0`
- L2: `small =. ;:'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'`
- L3: `tens =. ;:'zero zero twenty thirty forty fifty sixty seventy eighty ninety'`
- L4: `parts =. 0$<''`
- L5: `if. y>:100 do. parts =. parts,< (>(<.y%100){small),' hundred' end.`
- L6: `remainder =. 100|y`
- L7: `if. remainder>:20 do.`
- L8: `part =. >(<.remainder%10){tens`
- L9: `if. 0~:10|remainder do. part =. part,'-',>(10|remainder){small end.`
- L10: `parts =. parts,<part`
- L11: `elseif. remainder>0 do. parts =. parts,remainder{small`
- L12: `end.`
- L13: `}. ; (<' ') ,&.> parts`
- L16: `for_number. 0 13 40 100 568 71000 300019 999999 do.`
- L17: `parts =. 0$<''`
- L18: `if. number=0 do. parts =. <'zero' end.`
- L19: `if. number>:1000 do. parts =. parts,< (underthousand <.number%1000),' thousand' end.`
- L20: `if. 0~:1000|number do. parts =. parts,<underthousand 1000|number end.`
- L21: `words =. }. ; (<' ') ,&.> parts`

Minimization: The small-number helper, thousand composition and named final word result are needed for these three cases. Other input literals and numeric-prefix output are not necessary to derive the word expressions. The selected complete original lines, in source order, cost 426 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 438, and the complete source costs 464. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
