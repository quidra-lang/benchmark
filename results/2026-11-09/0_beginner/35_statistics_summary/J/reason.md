# Task B: 35_statistics_summary / J

The eleven samples contain 85 three times; every other sample appears once, so mode=85. Candidates are compared by frequency, with ascending numeric candidate order resolving equal maxima toward the smaller number. A strict greater frequency can replace the current choice; an equal frequency leaves the earlier/smaller candidate selected.

The sorted distinct values and equality counts align frequencies to ascending candidates; the first index of the maximum count implements the tie-break.

Evidence is from `main.ijs`, L2,L4,L5,L6,L7.

- L2: `values =. 72 85 64 90 85 58 77 85 69 93 71`
- L4: `ordered =. /:~values`
- L5: `candidates =. ~.ordered`
- L6: `counts =. +/"1 candidates =/ values`
- L7: `mode =. (counts i. >./counts){candidates`

Minimization: The actual samples, frequency construction and first-maximum selection are sufficient. Other descriptive-statistics calculations and formatting are irrelevant; R has several output fields on the same unavoidable line. The selected complete original lines, in source order, cost 89 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 103, and the complete source costs 260. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
