# Task B: 47_student_records / J

Apply a local trim of leading and trailing ASCII space characters to the actual name binding before any sorting, record construction or output reads it. For ` Tanaka ` the normalized value is `Tanaka`, with letter case unchanged. Do not lowercase names or alter scores/ranking rules; do not remove embedded spaces.

Normalize each element of names before constructing students and computing its alphabetic order. Use an edge-space trim, not a word-normalizer that collapses internal spaces.

Evidence is from `main.ijs`, L2,L4,L6.

- L2: `names =. ;:'Tanaka Suzuki Yamada Ito Kato Mori'`
- L4: `students =. names,.<"0 +/"1 scores`
- L6: `alpha =. /:names`

Minimization: The local field binding and its first relevant consumers identify the normalization site. Score arithmetic and the rest of ranking need no selection for this expression change. The selected complete original lines, in source order, cost 46 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 122, and the complete source costs 289. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
