# Task B: 45_anagram_groups / R

Apple has the sorted-letter signature `aelpp`, compared exactly as a whole key. No preceding anagram class has that signature, so it chooses a new group rather than an existing one. This is an absent-signature decision, not a test based on the first character or a partial match.

The sorted-character signatures become factor levels in unique(signatures) order; split assigns the first apple signature its own level/group. No mutable absent-entry increment is used.

Evidence is from `main.R`, L1,L2,L4,L5,L6,L7,L8.

- L1: `words <- c(`
- L2: `"listen", "stone", "night", "silent", "notes", "apple", "thing", "enlist", "earth", "onset",`
- L4: `)`
- L5: `signatures <- vapply(words, function(word) {`
- L6: `paste(sort(strsplit(word, "", fixed = TRUE)[[1]], method = "radix"), collapse = "")`
- L7: `}, character(1))`
- L8: `groups <- split(words, factor(signatures, levels = unique(signatures)))`

Minimization: The key representation and actual absent-class/group-selection operation are needed. Prior words are included only where necessary to establish apple is a new signature; output ordering and formatting are outside scope. The selected complete original lines, in source order, cost 153 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 163, and the complete source costs 204. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
