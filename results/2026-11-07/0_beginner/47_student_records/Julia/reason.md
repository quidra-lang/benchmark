# Task B: 47_student_records / Julia

Apply a local trim of leading and trailing ASCII space characters to the actual name binding before any sorting, record construction or output reads it. For ` Tanaka ` the normalized value is `Tanaka`, with letter case unchanged. Do not lowercase names or alter scores/ranking rules; do not remove embedded spaces.

The comprehension binds name=row[1]; normalize that string there before the student tuple exposes it to sorting/output (for example strip with the ASCII-space character set).

Evidence is from `main.jl`, L12.

- L12: `students = [(name = row[1], total = row[2]+row[3]+row[4]) for row in data]`

Minimization: The local field binding and its first relevant consumers identify the normalization site. Score arithmetic and the rest of ranking need no selection for this expression change. The selected complete original lines, in source order, cost 46 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 46, and the complete source costs 362. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
