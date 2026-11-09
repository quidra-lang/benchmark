# Task B: 35_statistics_summary / R

The eleven samples contain 85 three times; every other sample appears once, so mode=85. Candidates are compared by frequency, with ascending numeric candidate order resolving equal maxima toward the smaller number. A strict greater frequency can replace the current choice; an equal frequency leaves the earlier/smaller candidate selected.

table(numbers) orders numeric level names; the mode expression takes the first entry whose frequency equals the maximum.

Evidence is from `main.R`, L1,L10,L13.

- L1: `numbers <- c(72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71)`
- L10: `frequencies <- table(numbers)`
- L13: `average, ordered[6], as.integer(names(frequencies)[which.max(frequencies)]),`

Minimization: The actual samples, frequency construction and first-maximum selection are sufficient. Other descriptive-statistics calculations and formatting are irrelevant; R has several output fields on the same unavoidable line. The selected complete original lines, in source order, cost 88 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 218, and the complete source costs 240. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
