# Task B: 45_anagram_groups / J

Apple has the sorted-letter signature `aelpp`, compared exactly as a whole key. No preceding anagram class has that signature, so it chooses a new group rather than an existing one. This is an absent-signature decision, not a test based on the first character or a partial match.

The signature vector is sorted letters for each word. used skips already grouped indices; for apple, the equality mask identifies its own new signature class and marks that class used. There is no dictionary missing-key lookup in this implementation.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L10.

- L2: `words =. ;:'listen stone night silent notes apple thing enlist earth onset heart tones'`
- L3: `signatures =. /:~&.>words`
- L4: `used =. (#words)$0`
- L5: `for_i. i.#words do.`
- L6: `if. i{used do. continue. end.`
- L7: `mask =. (i{signatures)-:&>signatures`
- L8: `group =. mask#words`
- L10: `used =. used+.mask`

Minimization: The key representation and actual absent-class/group-selection operation are needed. Prior words are included only where necessary to establish apple is a new signature; output ordering and formatting are outside scope. The selected complete original lines, in source order, cost 113 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 133, and the complete source costs 153. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
