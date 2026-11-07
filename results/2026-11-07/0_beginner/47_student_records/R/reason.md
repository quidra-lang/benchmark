# Task B: 47_student_records / R

Apply a local trim of leading and trailing ASCII space characters to the actual name binding before any sorting, record construction or output reads it. For ` Tanaka ` the normalized value is `Tanaka`, with letter case unchanged. Do not lowercase names or alter scores/ranking rules; do not remove embedded spaces.

Normalize names before data.frame(name=names,...) and order uses students$name; trimws with an ASCII-space-only whitespace pattern meets the proposed contract.

Evidence is from `main.R`, L1,L3,L4.

- L1: `names <- c("Tanaka", "Suzuki", "Yamada", "Ito", "Kato", "Mori")`
- L3: `students <- data.frame(name = names, total = rowSums(scores))`
- L4: `ordered <- order(-students$total, students$name, method = "radix")`

Minimization: The local field binding and its first relevant consumers identify the normalization site. Score arithmetic and the rest of ranking need no selection for this expression change. The selected complete original lines, in source order, cost 88 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 183, and the complete source costs 279. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
